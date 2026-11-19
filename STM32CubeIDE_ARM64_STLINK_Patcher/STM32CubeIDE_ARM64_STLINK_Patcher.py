#!/usr/bin/env python3
"""STM32CubeIDE ST-LINK firmware-validation bypass. Standard library only."""
import os, sys, struct, shutil, zipfile, tempfile, pathlib, threading, subprocess
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

TARGET = 'com/st/stm32cube/ide/mcu/debug/stlinkfwutil/StLinkFwUtil.class'
PREFIX = 'com.st.stm32cube.ide.mcu.debug_'

class PatchError(Exception): pass

def u2(b,p): return struct.unpack_from('>H',b,p)[0]
def u4(b,p): return struct.unpack_from('>I',b,p)[0]
def p2(v): return struct.pack('>H',v)
def p4(v): return struct.pack('>I',v)

def patch_class(raw):
    """Replace exactly public static validate(String):boolean Code attribute."""
    b=raw; pos=0
    if b[:4]!=b'\xca\xfe\xba\xbe': raise PatchError('Invalid Java class file')
    pos=8; cp_count=u2(b,pos); pos+=2; cp={}; i=1
    while i<cp_count:
        tag=b[pos];pos+=1
        if tag==1:
            n=u2(b,pos);pos+=2; cp[i]=b[pos:pos+n].decode('utf-8','replace');pos+=n
        elif tag in (3,4,9,10,11,12,17,18): pos+=4
        elif tag in (5,6): pos+=8;i+=1
        elif tag in (7,8,16,19,20): pos+=2
        elif tag==15:pos+=3
        else:raise PatchError('Unsupported constant pool tag '+str(tag))
        i+=1
    pos+=6 # access flags, this class, super class
    n=u2(b,pos);pos+=2+2*n # interfaces
    def skip_members(pos):
        count=u2(b,pos);pos+=2
        for _ in range(count):
            pos+=6; ac=u2(b,pos);pos+=2
            for _ in range(ac):pos+=6+u4(b,pos+2)
        return pos
    pos=skip_members(pos) # fields
    mc=u2(b,pos);pos+=2
    found=[]
    for _ in range(mc):
        start=pos; flags=u2(b,pos);name=cp.get(u2(b,pos+2));desc=cp.get(u2(b,pos+4));pos+=6
        ac=u2(b,pos);pos+=2
        attrs=[]
        for _ in range(ac):
            astart=pos; idx=u2(b,pos); length=u4(b,pos+2);pos+=6+length
            attrs.append((astart,pos,idx,cp.get(idx)))
        if name=='validate' and desc=='(Ljava/lang/String;)Z':
            if not (flags & 0x0001 and flags & 0x0008):raise PatchError('validate(String) is not public static')
            codes=[a for a in attrs if a[3]=='Code']
            if len(codes)!=1:raise PatchError('Expected one Code attribute')
            astart,aend,idx,_=codes[0]
            payload=b[astart+6:aend]
            if len(payload)<8:raise PatchError('Malformed Code attribute')
            max_locals=u2(payload,2)
            if max_locals<1:raise PatchError('Unexpected method locals')
            # code: iconst_1; ireturn. No exception table or nested attributes.
            newcode=p2(1)+p2(max_locals)+p4(2)+b'\x04\xac'+p2(0)+p2(0)
            newattr=p2(idx)+p4(len(newcode))+newcode
            newmethod=b[start:astart]+newattr+b[aend:pos]
            found.append((start,pos,newmethod,payload))
    if len(found)!=1:raise PatchError(f'Expected one validate(String):boolean; found {len(found)}')
    start,end,newmethod,oldcode=found[0]
    # A prior patch already has the same 2-byte implementation.
    if u4(oldcode,4)==2 and oldcode[8:10]==b'\x04\xac': return raw,False
    return b[:start]+newmethod+b[end:],True

def find_plugins(folder):
    root=pathlib.Path(folder)
    if root.is_file():root=root.parent
    candidates=[root/'plugins',root/'STM32CubeIDE'/'plugins',root.parent/'plugins']
    for base in (root,root.parent):
        if base.is_dir():
            try:
                candidates += [p for p in base.iterdir() if p.is_dir() and p.name.lower()=='plugins']
            except OSError:pass
    for p in dict.fromkeys(candidates):
        if p.is_dir():return p
    raise PatchError('No plugins folder found. Select the STM32CubeIDE installation folder or executable.')

def discover(folder):
    plugins=find_plugins(folder)
    matches=[]
    for p in plugins.glob(PREFIX+'*.jar'):
        try:
            with zipfile.ZipFile(p) as z:
                if TARGET in z.namelist():
                    patch_class(z.read(TARGET)) # validate class structure
                    matches.append(p)
        except (zipfile.BadZipFile,PatchError):continue
    if not matches:raise PatchError('No compatible debug JAR found in '+str(plugins))
    return sorted(matches,key=lambda p:p.name,reverse=True)

def patch_jar(path):
    path=pathlib.Path(path);backup=path.with_name(path.name+'.bak')
    if backup.exists():raise PatchError('Backup already exists; refusing to overwrite: '+str(backup))
    with zipfile.ZipFile(path,'r') as zin:
        old=zin.read(TARGET);new,changed=patch_class(old)
        if not changed:raise PatchError('JAR already patched; no changes made.')
        # Build and test replacement before touching the installed file.
        fd,tmp=tempfile.mkstemp(suffix='.jar',dir=path.parent);os.close(fd)
        try:
            with zipfile.ZipFile(tmp,'w') as zout:
                for info in zin.infolist():
                    data=new if info.filename==TARGET else zin.read(info.filename)
                    zout.writestr(info,data)
            with zipfile.ZipFile(tmp) as test:
                if test.testzip() is not None or test.read(TARGET)!=new:raise PatchError('JAR verification failed')
        except BaseException:
            os.unlink(tmp);raise
    try:
        shutil.copy2(path,backup)
        os.replace(tmp,path)
    except BaseException:
        if os.path.exists(tmp):os.unlink(tmp)
        raise
    return backup

def restore_jar(path):
    path=pathlib.Path(path);backup=path.with_name(path.name+'.bak')
    if not backup.exists():raise PatchError('No .bak file found for selected JAR')
    with zipfile.ZipFile(backup) as z:
        if z.testzip() is not None or TARGET not in z.namelist():raise PatchError('Backup failed verification')
    fd,tmp=tempfile.mkstemp(suffix='.jar',dir=path.parent);os.close(fd)
    try:
        shutil.copy2(backup,tmp)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)
    return backup

class UI:
    def __init__(self,root):
        self.root=root;root.title('STM32CubeIDE ARM64 ST-LINK Patcher');root.geometry('830x470');root.minsize(700,380)
        self.location=tk.StringVar();self.selected=tk.StringVar();self.matches=[]
        frm=ttk.Frame(root,padding=16);frm.pack(fill='both',expand=True)
        ttk.Label(frm,text='STM32CubeIDE ARM64 ST-LINK Patcher',font=('Segoe UI',16,'bold')).pack(anchor='w')
        ttk.Label(frm,text='Select the STM32CubeIDE installation directory or STM32CubeIDE.exe. Close CubeIDE before patching.').pack(anchor='w',pady=(5,15))
        line=ttk.Frame(frm);line.pack(fill='x');ttk.Entry(line,textvariable=self.location).pack(side='left',fill='x',expand=True)
        ttk.Button(line,text='Browse Folder',command=self.browse_folder).pack(side='left',padx=(8,0))
        ttk.Button(line,text='Browse EXE',command=self.browse_exe).pack(side='left',padx=(8,0))
        ttk.Button(frm,text='Scan Plugins',command=self.scan).pack(anchor='w',pady=10)
        ttk.Label(frm,text='Compatible debug plugin JAR:').pack(anchor='w')
        self.combo=ttk.Combobox(frm,textvariable=self.selected,state='readonly');self.combo.pack(fill='x',pady=(4,12))
        buttons=ttk.Frame(frm);buttons.pack(fill='x')
        ttk.Button(buttons,text='Patch Selected JAR',command=self.patch).pack(side='left')
        ttk.Button(buttons,text='Restore Original (.bak)',command=self.restore).pack(side='left',padx=10)
        ttk.Label(frm,text='Activity log:').pack(anchor='w',pady=(16,3))
        self.logbox=tk.Text(frm,height=10,wrap='word',state='disabled');self.logbox.pack(fill='both',expand=True)
        self.log('This tool changes only public static boolean validate(String) in StLinkFwUtil.class.')
        self.log('Original JAR is preserved as <filename>.jar.bak. No external Python packages required.')
    def log(self,s):
        self.logbox.configure(state='normal');self.logbox.insert('end',s+'\n');self.logbox.see('end');self.logbox.configure(state='disabled')
    def browse_folder(self):
        p=filedialog.askdirectory(title='Select STM32CubeIDE installation folder')
        if p:self.location.set(p);self.scan()
    def browse_exe(self):
        p=filedialog.askopenfilename(title='Select STM32CubeIDE executable',filetypes=[('Executable','*.exe'),('All files','*.*')])
        if p:self.location.set(p);self.scan()
    def scan(self):
        try:
            self.matches=discover(self.location.get());self.combo['values']=[str(x) for x in self.matches];self.selected.set(str(self.matches[0]));self.log(f'Found {len(self.matches)} compatible JAR(s).')
            for x in self.matches:self.log('  '+str(x))
        except Exception as e:self.matches=[];self.combo['values']=[];self.selected.set('');self.log('Scan failed: '+str(e));messagebox.showerror('Scan failed',str(e))
    def get_path(self):
        p=self.selected.get()
        if not p or pathlib.Path(p) not in self.matches:raise PatchError('Scan and select a compatible JAR first')
        return pathlib.Path(p)
    def patch(self):
        try:
            p=self.get_path()
            if not messagebox.askyesno('Confirm patch','Close STM32CubeIDE first.\n\nBack up and patch:\n'+str(p)+'\n\nContinue?'):return
            bak=patch_jar(p);self.log('PATCHED: '+str(p));self.log('BACKUP: '+str(bak));messagebox.showinfo('Patch complete','JAR patched successfully.\nBackup: '+str(bak))
        except Exception as e:self.log('Patch failed: '+str(e));messagebox.showerror('Patch failed',str(e))
    def restore(self):
        try:
            p=self.get_path()
            if not messagebox.askyesno('Restore original','Close STM32CubeIDE first.\n\nRestore from .bak for:\n'+str(p)+'?'):return
            bak=restore_jar(p);self.log('RESTORED from '+str(bak));messagebox.showinfo('Restored','Original JAR restored. Backup retained.')
        except Exception as e:self.log('Restore failed: '+str(e));messagebox.showerror('Restore failed',str(e))

if __name__=='__main__':
    root=tk.Tk();UI(root);root.mainloop()

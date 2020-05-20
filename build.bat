@echo off
echo Check for fasm.exe...
if not exist C:\fasmw17324\fasm.exe (
    echo FAIL: Plz, specify path to FASM compier!
    pause
    exit
)

echo Building bootloader...
cd source
C:\fasmw17324\fasm.exe boot.asm
move boot.img ..\build\MargOS.img

echo Building kernel...
C:\fasmw17324\fasm.exe kernel.asm
move kernel.bin ..\build\MARGOSKR.BIN
cd ..

echo Copying the kernel and apps to the disk image...
imdisk -a -f build\MargOS.img -s 1440K -m B:
copy build\MARGOSKR.BIN b:\
copy build\games\*.COM b:\
copy build\*.COM b:\
imdisk -D -m B:

echo BUILD OK!
pause
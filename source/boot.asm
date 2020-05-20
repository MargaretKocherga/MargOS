format binary as 'img'
use16

; BIOS will load this to 0x7C00
; Bootloader starts with FAT12 info
BS_jmpBoot:
                jmp     boot_start
                db      3 - $ dup($90)

BS_OEMName     db      "MSWIN5.0"
BPB_BytsPerSec dw      512
BPB_SecPerClus db      1
BPB_RsvdSecCnt dw      1
BPB_NumFATs    db      2
BPB_RootEntCnt dw      224
BPB_TotSec16   dw      2880
BPB_Media      db      0F0h
BPB_FATSz16    dw      9
BPB_SecPerTrk  dw      18
BPB_NumHeads   dw      2
BPB_HiddSec    dd      0
BPB_TotSec32   dd      0
BS_DrvNum      db      0
BS_Reserved1   db      0
BS_BootSig     db      029h
BS_VolID       dd      %t
BS_VolLab      db      "MARGOS     "  
BS_FilSysType  db      "FAT12   "

boot_start:
    xor ax,ax
    ;mov ax, 07C0h       ; Compute the stack segment
    ;add ax, 544         ; 32 (bootloader size) + 512(buffer for File Alloc Table)
    cli
    mov ss, ax
    mov sp, 7BFEh        ; Stack size
    sti

    mov ax, 07C0h
    mov ds, ax

    mov byte [bootdisk], dl     ; DL still have the boot disk number, store it

    mov ax, 60h                 ; Add interrupt handler for adding other handlers
    mov dx, set_int_handler     ; Here goes some magic to call interrupt that hasn't been added to IVT yet (tricking IRET)
    pushf                       ; Flags for IRET
    call 07C0h:set_int_handler  ; Far call for IRET

    mov ax, 61h                 ; Now we can set other interrupts with 60h
    mov dx, read_from_disk
    int 60h

    mov ax, 62h
    mov dx, load_file_by_name
    int 60h

    mov dx, 90h
    mov gs, dx
    mov si, kern_name
    int 62h

    mov dl, byte [bootdisk]

    mov ax, 90h                   ; Init segment registers
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    jmp 90h:0h

;===================================================
;  int 62h - load file to buffer
;   DS:SI - Filename string
;   GS - segment location
load_file_by_name:
    mov bx, buffer       ; ES:BX - buffer where root directory from disk will be loaded
    mov ax, 0x07c0
    mov es, ax
    mov ax, 19           ; Sector with root directory
    mov cx, 14           ; Root directory size in sectors

    int 61h              ; read_from_disk

search_file:
    mov ax, 0x07c0       ; Set ES:DI to filename for cmpsb
    mov es, ax
    mov di, buffer

    mov cx, 224          ; Repeat comparison for max of 224 files in root directory
    mov dx, 0
    mov bx, si
next_filename:
    xchg cx, ax          ; Cycle in cycle, so save cx
    mov si, bx
    ;mov si, kern_name
    mov cx, 11           ; Filename max length  (because of FAT12 filename: 8.3)
    rep cmpsb            ; Compare next filename (ES:DI) with needed filename (DS:SI)
    je found_file

    add dx, 32
    mov di, buffer       ; Inc DI to the next filename
    add di, dx

    xchg ax, cx
    loop next_filename

    mov si, file_not_found  ; There's no file on the floppy - print error msg
    call print_string
    jmp reboot

found_file:
    push 0x07c0
    pop ds
    mov ax, word [es:di + $0F]    ; Get first file cluster from root directory
    mov word [cluster], ax        ; Save first file cluster

    mov ax, 1         ; File Allocation Table is on sector 1 (0 - bootloader)
    mov cx, 9         ; FAT size
    mov bx, buffer    ; Load FAT at 0x7E00

    int 61h

load_file_sector:  ; Actually is a cycle
    mov ax, gs                ; Kernel will be loaded to 0x0500 (0050:0000)
    mov es, ax
    mov bx, word [pointer]     ; Track the address we are writing to
    mov ax, word [cluster]     ; Track the cluster we are reading from
    add ax, 31
    mov cx, 1                  ; Read one cluster per time

    int 61h

calculate_next_cluster:
    mov ax, [cluster]
    mov dx, 0
    mov bx, 3
    mul bx
    mov bx, 2
    div bx
    mov si, buffer
    add si, ax
    mov ax, word [ds:si]
    or dx, dx
    jz even

odd:                            ; FAT12 is comlicated to parse :(
    shr ax, 4
    jmp short next_cluster

even:
    and ax, 0FFFh

next_cluster:
    mov word [cluster], ax

    cmp ax, 0FF8h               ; End of the file?
    jae boot_end                 ; If it is then execute kernel

    add word [pointer], 512
    jmp load_file_sector

boot_end:
    mov [pointer], 0
    iret

;-------------------------------------------------------------------
;                     Bootloader routines
;-------------------------------------------------------------------
reboot:
    xor ax, ax
    int 16h
    xor ax, ax
    int 19h

print_string:
    pusha
    mov ah, 0Eh
.repeat:
    lodsb
    cmp al, 0
    je  .done
    int 10h
    jmp .repeat
.done:
    popa
    ret

reset_floppy:
    push ax
    push dx
    xor ax,ax
    mov dl, byte [bootdisk]
    int 13h
    pop dx
    pop ax
    ret         
    
;===============================================
;  int 61h - read from floppy (wrapper over Int 13h)
;   ES:BX - location
;   AX - first sector number
;   CX - size in sectors
read_from_disk:
    push ds
    push 0x07c0
    pop ds
    push cx

    push ax
    xor dx, dx
    div word [BPB_SecPerTrk]
    add dl, 01h
    mov cl, dl

    pop ax
    xor dx, dx
    div word [BPB_SecPerTrk]
    xor dx, dx
    div word [BPB_NumHeads]
    mov dh, dl
    mov ch, al

    mov dl, byte [bootdisk]
    pop ax
    mov ah, 2

    pusha
.retry:
    popa
    pusha

    int 13h
    jnc .ok
    call reset_floppy
    jnc .retry
    jmp reboot

.ok:
    popa
    pop ds
    iret

;===============================================
;  int 60h - set interrupt vector
;   AL - interrupt number
;   DS:DX - new interrupt handler
set_int_handler:   
    xor bx, bx     ; Interupt address is at segment = 0, offset = intNum * 4
    mov es, bx     ; So we need 0 in ES
    xor ah, ah
    shl ax, 2      ; Get interrupt address in IVT (multiply interrupt number to 4)
    mov di, ax
    mov bx, ds
    cli
    xchg [es:di], dx    ; Offset
    xchg [es:di+2], bx  ; Segment
iret



;--------------------------------------------------

    kern_name       db "MARGOSKRBIN"   ; "MARGOSKR.BIN"
    file_not_found  db "MARGOSKR.BIN is not found!", 0

    bootdisk   db 0
    cluster    dw 0
    pointer    dw 0



    db      510 - $ dup($00)
    db      $55, $AA
;---------------------------------------------------
;           End of the bootloader segment
;---------------------------------------------------
buffer:

FAT1:
    db      $F0, $FF, $FF
    db      9 * 512 - ($ - FAT1) dup ($00)

FAT2:      ; the same as the FAT1
    repeat 9 * 512
        load a byte from FAT1 + % - 1
        db a
    end repeat

root_dir:

                db 224 * 32 - ($ - root_dir) dup($00)
files:
                db 2880 * 512 - $ dup($00)


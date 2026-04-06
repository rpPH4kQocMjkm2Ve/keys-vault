; keys-vault — FBE via gocryptfs + GNOME Keyring (x86_64 Linux assembly)
; Complete implementation
;
; Build: make build

BITS 64

; ═══════════════════════════════════════════════════════════
; SYSCALL DEFINITIONS
; ═══════════════════════════════════════════════════════════
%define SYS_READ        0
%define SYS_WRITE       1
%define SYS_OPEN        2
%define SYS_CLOSE       3
%define SYS_STAT        4
%define SYS_MMAP        9
%define SYS_MUNMAP     11
%define SYS_EXECVE     59
%define SYS_EXIT       60
%define SYS_FORK       57
%define SYS_WAIT4      61
%define SYS_PIPE       22
%define SYS_DUP2       33

%define O_RDONLY        0
%define O_WRONLY        1
%define O_CREAT      0x40
%define O_TRUNC      0x200

%define STAT_SIZE     128
%define MAX_PATH      512
%define BUF_SIZE     4096
%define MAX_PASS      256
%define MAX_ARGS     16

%define STDIN         0
%define STDOUT        1
%define STDERR        2
%define EXIT_SUCCESS  0
%define EXIT_FAILURE  1

section .data
    version_str     db  "1.0.0", 10, 0
    err_prefix      db  "keys-vault: ", 0
    nl              db  10, 0
    
    ; External binaries
    bin_gocryptfs   db  "/usr/bin/gocryptfs", 0
    bin_secret      db  "/usr/bin/secret-tool", 0  
    bin_fusermount  db  "/usr/bin/fusermount", 0
    bin_mkdir       db  "/usr/bin/mkdir", 0
    bin_rm          db  "/usr/bin/rm", 0
    
    ; gocryptfs args
    gfs_init        db  "-init", 0
    gfs_q           db  "-q", 0
    gfs_passwd      db  "-passwd", 0
    gfs_dd          db  "--", 0
    gfs_conf        db  "/gocryptfs.conf", 0
    
    ; fusermount args
    fm_u            db  "-u", 0
    fm_uz           db  "-uz", 0
    
    ; mkdir args
    mkdir_p         db  "-p", 0
    
    ; rm args
    rm_rf           db  "-rf", 0
    
    ; secret-tool args
    st_store        db  "store", 0
    st_lookup       db  "lookup", 0
    st_app          db  "application", 0
    st_label_pfx    db  "--label=keys-vault passphrase (", 0
    st_label_sfx    db  ")", 0
    kr_attr_pfx     db  "keys-vault:", 0
    
    ; Paths
    proc_mounts     db  "/proc/mounts", 0
    fuse_marker     db  " fuse.", 0
    dev_urandom     db  "/dev/urandom", 0
    b64_alpha       db  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    
    ; Messages - status
    msg_not_init    db  "not initialized", 10, 0
    msg_open        db  "open", 10, 0
    msg_locked      db  "locked", 10, 0
    msg_stale       db  "stale", 10, 0
    msg_init_ok     db  10, "Initialized. Run: keys-vault open", 10, 0
    msg_passwd_ok   db  "Passphrase rotated and updated in keyring.", 10, 0
    msg_recover     db  "keys-vault: recovering stale FUSE mount at ", 0
    
    ; Messages - prompts
    msg_pass1       db  "Passphrase: ", 0
    msg_pass2       db  "Confirm:    ", 0
    msg_choice1     db  "1) Generate random passphrase", 10, 0
    msg_choice2     db  "2) Enter your own", 10, 0
    msg_choice_q    db  "Choice [1/2]: ", 0
    msg_gen_hdr     db  10, "Generated passphrase (save it — e.g. in KeePassXC):", 10, "    ", 0
    msg_gen_ftr     db  10, 10, "It will be stored in GNOME Keyring for automatic unlock.", 10, 0
    
    ; Messages - errors
    err_empty       db  "empty passphrase", 0
    err_nomatch     db  "passphrases do not match", 0
    err_already     db  "already initialized (", 0
    err_notempty    db  " is not empty.", 10, "Move or back up its contents first, then run init again.", 10, "After 'keys-vault init' and 'keys-vault open' you can copy them into the mounted volume.", 10, 0
    err_init_fail   db  "gocryptfs -init failed", 0
    err_mount_fail  db  "mount failed", 0
    err_umount_fail db  "unmount failed", 0
    err_keyring     db  "keyring lookup failed (is gnome-keyring unlocked?)", 0
    err_passwd_fail db  "gocryptfs -passwd failed", 0
    err_no_current  db  "cannot read current passphrase from keyring", 0
    err_not_init_c  db  "not initialized — run: keys-vault init", 0
    err_unk_cmd     db  "unknown command: ", 0
    err_unk_opt     db  "unknown option: ", 0
    err_unexp_arg   db  "unexpected argument: ", 0
    err_cant_umnt   db  "cannot unmount stale ", 0
    err_pass_in     db  "passphrase input failed", 0
    err_dir_req     db  "--dir requires a value", 0
    err_cipher_req  db  "--cipher-dir requires a value", 0
    err_unk_key     db  "unknown config key ignored: ", 0
    
    ; Usage text
    usage_text      db  "Usage: keys-vault [options] <command>", 10, 10
                    db  "Commands:", 10
                    db  "    init     Create encrypted volume, store passphrase in keyring", 10
                    db  "    open     Mount vault (passphrase from keyring)", 10
                    db  "    close    Unmount vault", 10
                    db  "    status   Print state: open / locked / stale / not initialized", 10
                    db  "    passwd   Rotate gocryptfs passphrase and update keyring", 10, 10
                    db  "Options:", 10
                    db  "    --dir=PATH         Plaintext mount point (default: ~/keys)", 10
                    db  "    --cipher-dir=PATH  Encrypted ciphertext directory", 10
                    db  "                       (default: derived from --dir)", 10
                    db  "    -h, --help         Show this help", 10
                    db  "    --version          Show version", 10, 10
                    db  "Configuration:", 10
                    db  "    /etc/keys-vault.conf                             System defaults", 10
                    db  "    ${XDG_CONFIG_HOME:-~/.config}/keys-vault.conf    User overrides", 10, 10
                    db  "    Set PLAIN_DIR and/or CIPHER_DIR in config files.", 10
                    db  "    CLI flags take precedence over config files.", 10, 0
    
    ; Config
    conf_sys        db  "/etc/keys-vault.conf", 0
    key_plain       db  "PLAIN_DIR=", 0
    key_cipher      db  "CIPHER_DIR=", 0
    key_plain_noeq  db  "PLAIN_DIR", 0
    key_cipher_noeq db  "CIPHER_DIR", 0
    default_plain   db  "/keys", 0
    dot_enc         db  ".enc", 0
    
    ; Commands
    cmd_init_s      db  "init", 0
    cmd_open_s      db  "open", 0
    cmd_close_s     db  "close", 0
    cmd_status_s    db  "status", 0
    cmd_passwd_s    db  "passwd", 0
    
    ; Mountpoint binary check
    bin_mountpoint  db  "/usr/bin/mountpoint", 0
    mp_q            db  "-q", 0

section .bss
    ; Global state
    home_dir        resb MAX_PATH
    final_plain     resb MAX_PATH
    final_cipher    resb MAX_PATH
    has_cipher      resb 1
    cmd_str         resb 16
    kr_attr         resb MAX_PATH
    conf_plain      resb MAX_PATH
    conf_cipher     resb MAX_PATH
    arg_plain       resb MAX_PATH
    arg_cipher      resb MAX_PATH
    
    ; Buffers
    buf_read        resb BUF_SIZE
    buf_line        resb 256
    buf_pass        resb MAX_PASS
    buf_pass2       resb MAX_PASS
    buf_gen         resb 64
    buf_b64         resb 64
    buf_mounts      resb BUF_SIZE
    statbuf         resb STAT_SIZE
    pipe_fds        resd 2
    wait_st         resd 1
    
    ; exec arrays
    exec_argv       resq MAX_ARGS
    envp_global     resq 1

; We'll compute environ at startup from the stack
; No extern needed

section .text
global _start

; ──────────────────────────────────────────────────────────
; SYSCALL WRAPPERS
; ──────────────────────────────────────────────────────────

sys_exit:
    mov rax, SYS_EXIT
    syscall
    ret

sys_read:
    mov rax, SYS_READ
    syscall
    ret

sys_write:
    mov rax, SYS_WRITE
    syscall
    ret

sys_open:
    mov rax, SYS_OPEN
    syscall
    ret

sys_close:
    mov rax, SYS_CLOSE
    syscall
    ret

sys_stat:
    mov rax, SYS_STAT
    syscall
    ret

sys_execve:
    mov rax, SYS_EXECVE
    syscall
    ret

sys_fork:
    mov rax, SYS_FORK
    syscall
    ret

sys_wait4:
    mov rax, SYS_WAIT4
    syscall
    ret

sys_pipe:
    mov rax, SYS_PIPE
    syscall
    ret

sys_dup2:
    mov rax, SYS_DUP2
    syscall
    ret

; ──────────────────────────────────────────────────────────
; STRING UTILITIES
; ──────────────────────────────────────────────────────────

; strlen: rdi=str → rax=len
my_strlen:
    push rdi
    xor rcx, rcx
.str_loop:
    mov al, [rdi+rcx]
    test al, al
    jz .str_done
    inc rcx
    jmp .str_loop
.str_done:
    mov rax, rcx
    pop rdi
    ret

; strcpy: rdi=dst, rsi=src
my_strcpy:
    push rdi
    push rsi
.cp_loop:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .cp_done
    inc rsi
    inc rdi
    jmp .cp_loop
.cp_done:
    pop rsi
    pop rdi
    ret

; strcmp: rdi=a, rsi=b → rax=0 if equal
my_strcmp:
    push rdi
    push rsi
.cmp_loop:
    mov al, [rdi]
    mov bl, [rsi]
    cmp al, bl
    jne .cmp_ne
    test al, al
    jz .cmp_eq
    inc rdi
    inc rsi
    jmp .cmp_loop
.cmp_eq:
    xor rax, rax
    pop rsi
    pop rdi
    ret
.cmp_ne:
    movzx rax, al
    movzx rbx, bl
    sub rax, rbx
    pop rsi
    pop rdi
    ret

; strchr: rdi=s, rsi=c → rax=ptr or 0
my_strchr:
    push rdi
.ch_loop:
    mov al, [rdi]
    test al, al
    jz .ch_nf
    cmp al, sil
    je .ch_found
    inc rdi
    jmp .ch_loop
.ch_found:
    mov rax, rdi
    pop rdi
    ret
.ch_nf:
    xor rax, rax
    pop rdi
    ret

; print_str_stdout: rdi=str
print_str_stdout:
    push rdi        ; Save string pointer
    call my_strlen  ; rax = length
    mov rdx, rax    ; rdx = length
    pop rsi         ; rsi = string pointer
    mov rdi, STDOUT
    mov rax, SYS_WRITE
    syscall
    ret

; print_str_stderr: rdi=str
print_str_stderr:
    push rdi        ; Save string pointer
    call my_strlen  ; rax = length
    mov rdx, rax    ; rdx = length
    pop rsi         ; rsi = string pointer
    mov rdi, STDERR
    mov rax, SYS_WRITE
    syscall
    ret

; die: rdi=msg → print and exit 1
die:
    push rdi
    lea rdi, [rel err_prefix]
    call print_str_stderr
    pop rdi
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit

; ──────────────────────────────────────────────────────────
; PROCESS EXECUTION
; ──────────────────────────────────────────────────────────

; run_with_stdin: rdi=argv_ptr, rsi=data, rdx=len → rax=exit_code
run_with_stdin:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx
    push r12
    push r13
    push r14
    push r15
    
    ; Save parameters
    mov r12, rdi   ; argv
    mov r13, rsi   ; data
    mov r14, rdx   ; len
    
    ; Create pipe
    lea rdi, [rel pipe_fds]
    mov rax, SYS_PIPE
    syscall
    cmp rax, 0
    jl .rw_fail
    
    mov r15d, [rel pipe_fds]       ; pipe[0] read
    lea rdi, [rel pipe_fds]
    mov ebx, [rdi+4]      ; pipe[1] write
    
    ; Fork
    mov rax, SYS_FORK
    syscall
    test rax, rax
    js .rw_fail
    jz .rw_child
    
    ; Parent
    mov r14, rax  ; child pid
    
    ; Close read end
    mov rdi, r15
    call sys_close
    
    ; Write data
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rax, SYS_WRITE
    syscall
    
    ; Close write end
    mov rdi, rbx
    call sys_close
    
    ; Wait for child
    mov rdi, r14
    lea rsi, [rel wait_st]
    xor rdx, rdx
    xor r10, r10
    mov rax, SYS_WAIT4
    syscall
    
    ; Get exit status
    mov eax, [rel wait_st]
    shr eax, 8
    jmp .rw_done
    
.rw_child:
    ; Child: close write, dup2 read→stdin, exec
    mov rdi, rbx
    call sys_close
    
    mov rdi, r15
    mov rsi, STDIN
    mov rax, SYS_DUP2
    syscall
    
    mov rdi, r15
    call sys_close
    
    ; Exec
    mov rdi, r12
    lea rsi, [rel envp_global]
    mov rax, SYS_EXECVE
    syscall
    
    ; If exec fails
    mov rdi, EXIT_FAILURE
    call sys_exit
    
.rw_fail:
    mov rax, EXIT_FAILURE
    
.rw_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

; run_simple: rdi=argv_ptr → rax=exit_code
run_simple:
    push rbp
    mov rbp, rsp
    push r12
    
    mov r12, rdi
    
    ; Fork
    mov rax, SYS_FORK
    syscall
    test rax, rax
    js .rs_fail
    jz .rs_child
    
    ; Parent
    mov r14, rax
    mov rdi, r14
    lea rsi, [rel wait_st]
    xor rdx, rdx
    xor r10, r10
    mov rax, SYS_WAIT4
    syscall
    
    mov eax, [rel wait_st]
    shr eax, 8
    jmp .rs_done
    
.rs_child:
    ; Child: exec
    mov rdi, r12
    lea rsi, [rel envp_global]
    mov rax, SYS_EXECVE
    syscall
    mov rdi, EXIT_FAILURE
    call sys_exit
    
.rs_fail:
    mov rax, EXIT_FAILURE
    
.rs_done:
    pop r12
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; HELPERS
; ──────────────────────────────────────────────────────────

; is_initialized: rdi=cipher_dir → rax=1 if initialized, 0 otherwise
is_initialized:
    push rdi
    push rsi
    push rdx
    push rcx
    
    ; Build path: cipher_dir + "/gocryptfs.conf"
    lea rsi, [rel buf_read]
    call my_strcpy
    
    call my_strlen
    lea rdi, [rel buf_read]
    add rdi, rax
    lea rsi, [rel gfs_conf]
    call my_strcpy
    
    ; Stat the file
    lea rdi, [rel buf_read]
    lea rsi, [rel statbuf]
    mov rax, SYS_STAT
    syscall
    
    test rax, rax
    jnz .not_init
    mov rax, 1
    jmp .init_done
    
.not_init:
    xor rax, rax
    
.init_done:
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    ret

; is_mounted: rdi=mountpoint → rax=1 if mounted
is_mounted:
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    
    ; Open /proc/mounts
    lea rdi, [rel proc_mounts]
    xor rsi, rsi
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    test rax, rax
    js .not_mounted
    
    mov r12, rax  ; fd
    
    ; Read file
    mov rdi, r12
    lea rsi, [rel buf_mounts]
    mov rdx, BUF_SIZE
    mov rax, SYS_READ
    syscall
    
    mov r9, rax   ; bytes read
    mov rdi, r12
    call sys_close
    
    ; Search for mountpoint in buffer
    ; Look for " {mountpoint} " pattern
    lea r8, [rel buf_mounts]
    xor r10, r10  ; offset
    
.mount_search:
    cmp r10, r9
    jge .not_mounted
    
    ; Check if character matches start of mountpoint
    push rdi
    push rsi
    push rcx
    lea rdi, [rel final_plain]
    lea rsi, [r8+r10]
    call my_strcmp
    pop rcx
    pop rsi
    pop rdi
    test rax, rax
    je .found_mount
    
    inc r10
    jmp .mount_search
    
.found_mount:
    ; Check preceding char is space
    test r10, r10
    jz .not_mounted
    mov al, [r8+r10-1]
    cmp al, ' '
    jne .not_mounted
    
    ; Check following char is space or newline
    push rdi
    call my_strlen
    pop rdi
    add r10, rax
    mov al, [r8+r10]
    cmp al, ' '
    je .is_mounted_yes
    cmp al, 10
    je .is_mounted_yes
    
.not_mounted:
    xor rax, rax
    jmp .mount_done
    
.is_mounted_yes:
    mov rax, 1
    
.mount_done:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; is_stale: rdi=mountpoint → rax=1 if stale mount
is_stale:
    push rdi
    call is_mounted
    test rax, rax
    jz .not_stale
    
    ; Try to stat - if it fails, mount is stale
    lea rsi, [rel statbuf]
    mov rax, SYS_STAT
    syscall
    test rax, rax
    jnz .is_stale_yes
    
.not_stale:
    xor rax, rax
    pop rdi
    ret
    
.is_stale_yes:
    mov rax, 1
    pop rdi
    ret

; recover_stale: rdi=mountpoint
recover_stale:
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    
    call is_stale
    test rax, rax
    jz .rec_done
    
    ; Print recovery message
    lea rdi, [rel msg_recover]
    call print_str_stderr
    mov rdi, rdi  ; already in rdi
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    
    ; Try fusermount -u, then -uz
    lea r8, [rel exec_argv]
    lea r9, [rel bin_fusermount]
    mov [r8], r9
    lea r9, [rel fm_u]
    mov [r8+8], r9
    mov [r8+16], rdi
    mov qword [r8+24], 0
    
    mov rdi, r8
    call run_simple
    test rax, rax
    jz .rec_done
    
    ; Try -uz
    lea r9, [rel fm_uz]
    mov [r8+8], r9
    call run_simple
    
.rec_done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; build_kr_attr: rdi=mountpoint → stores in kr_attr
build_kr_attr:
    push rdi
    push rsi
    
    lea rsi, [rel kr_attr_pfx]
    lea rdi, [rel kr_attr]
    call my_strcpy
    
    call my_strlen
    lea rdi, [rel kr_attr]
    add rdi, rax
    ; rsi still has mountpoint
    call my_strcpy
    
    pop rsi
    pop rdi
    ret

; kr_store: rdi=passphrase, rsi=mountpoint
kr_store:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    
    mov r12, rdi  ; passphrase
    mov r13, rsi  ; mountpoint
    
    ; Build attribute
    mov rdi, rsi
    call build_kr_attr
    
    ; Build label: "--label=keys-vault passphrase (mountpoint)"
    lea rdi, [rel buf_read]
    lea rsi, [rel st_label_pfx]
    call my_strcpy
    
    call my_strlen
    lea rdi, [rel buf_read]
    add rdi, rax
    mov rsi, r13  ; mountpoint
    call my_strcpy
    
    call my_strlen
    lea rdi, [rel buf_read]
    add rdi, rax
    lea rsi, [rel st_label_sfx]
    call my_strcpy
    
    ; Build argv
    lea r8, [rel exec_argv]
    lea r9, [rel bin_secret]
    mov [r8], r9
    lea r9, [rel st_store]
    mov [r8+8], r9
    lea r9, [rel buf_read]  ; label
    mov [r8+16], r9
    lea r9, [rel st_app]
    mov [r8+24], r9
    lea r9, [rel kr_attr]
    mov [r8+32], r9
    mov qword [r8+40], 0
    
    ; Calculate passphrase length
    mov rdi, r12
    call my_strlen
    mov r14, rax
    
    ; Run with stdin
    mov rdi, r8
    mov rsi, r12
    mov rdx, r14
    call run_with_stdin
    
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; kr_lookup: rdi=mountpoint → rax=ptr to passphrase or 0
kr_lookup:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    
    mov r12, rdi  ; mountpoint
    
    ; Build attribute
    mov rdi, rdi
    call build_kr_attr
    
    ; Build argv
    lea r8, [rel exec_argv]
    lea r9, [rel bin_secret]
    mov [r8], r9
    lea r9, [rel st_lookup]
    mov [r8+8], r9
    lea r9, [rel st_app]
    mov [r8+16], r9
    lea r9, [rel kr_attr]
    mov [r8+24], r9
    mov qword [r8+32], 0
    
    ; Create pipe to capture stdout
    lea rdi, [rel pipe_fds]
    mov rax, SYS_PIPE
    syscall
    cmp rax, 0
    jl .kl_fail
    
    mov r13d, [rel pipe_fds]      ; read
    lea rdi, [rel pipe_fds]
    mov ebx, [rdi+4]     ; write
    
    ; Fork
    mov rax, SYS_FORK
    syscall
    test rax, rax
    js .kl_fail
    jz .kl_child
    
    ; Parent
    mov r14, rax
    
    ; Close write end
    mov rdi, rbx
    call sys_close
    
    ; Read from pipe
    mov rdi, r13
    lea rsi, [rel buf_pass]
    mov rdx, MAX_PASS
    mov rax, SYS_READ
    syscall
    
    ; Null-terminate
    lea rdi, [rel buf_pass]
    add rdi, rax
    mov byte [rdi], 0
    
    ; Close read end
    mov rdi, r13
    call sys_close
    
    ; Wait
    mov rdi, r14
    lea rsi, [rel wait_st]
    xor rdx, rdx
    xor r10, r10
    mov rax, SYS_WAIT4
    syscall
    
    mov eax, [rel wait_st]
    shr eax, 8
    test rax, rax
    jnz .kl_fail
    
    lea rax, [rel buf_pass]
    jmp .kl_done
    
.kl_child:
    ; Child: close read, dup2 write→stdout, exec
    mov rdi, r13
    call sys_close
    
    mov rdi, rbx
    mov rsi, STDOUT
    mov rax, SYS_DUP2
    syscall
    
    mov rdi, rbx
    call sys_close
    
    mov rdi, r8
    lea rsi, [rel envp_global]
    mov rax, SYS_EXECVE
    syscall
    mov rdi, EXIT_FAILURE
    call sys_exit
    
.kl_fail:
    xor rax, rax
    
.kl_done:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; read_pass: reads passphrase twice, compares → rax=ptr
read_pass:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    
    ; Prompt 1
    lea rdi, [rel msg_pass1]
    call print_str_stderr
    
    ; Read line 1
    lea rdi, [rel buf_pass]
    mov rsi, MAX_PASS-1
    call read_line_stdin
    test rax, rax
    jz .rp_empty
    
    ; Prompt 2
    lea rdi, [rel msg_pass2]
    call print_str_stderr
    
    ; Read line 2
    lea rdi, [rel buf_pass2]
    mov rsi, MAX_PASS-1
    call read_line_stdin
    test rax, rax
    jz .rp_empty
    
    ; Compare
    lea rdi, [rel buf_pass]
    lea rsi, [rel buf_pass2]
    call my_strcmp
    test rax, rax
    jnz .rp_nomatch
    
    lea rax, [rel buf_pass]
    jmp .rp_done
    
.rp_empty:
    lea rdi, [rel err_empty]
    call die
    
.rp_nomatch:
    lea rdi, [rel err_nomatch]
    call die
    
.rp_done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; read_line_stdin: rdi=buf, rsi=max → rax=len
read_line_stdin:
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    
    xor rcx, rcx  ; count
    
.rl_loop:
    cmp rcx, rsi
    jge .rl_done
    
    ; Read 1 byte
    mov rdi, STDIN
    lea r8, [rel buf_read]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    
    test rax, rax
    jz .rl_done
    
    mov al, [rel buf_read]
    cmp al, 10
    je .rl_done
    cmp al, 0
    je .rl_done
    
    mov [rdi+rcx], al
    inc rcx
    jmp .rl_loop
    
.rl_done:
    mov byte [rdi+rcx], 0
    mov rax, rcx
    
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    ret

; generate_pass: generates random passphrase → rax=ptr
generate_pass:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14
    
    ; Open /dev/urandom
    lea rdi, [rel dev_urandom]
    xor rsi, rsi
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    test rax, rax
    js .gp_fail
    mov r12, rax
    
    ; Read 32 bytes
    mov rdi, r12
    lea rsi, [rel buf_read]
    mov rdx, 32
    mov rax, SYS_READ
    syscall
    mov r13, rax  ; bytes read
    
    ; Close
    mov rdi, r12
    call sys_close
    
    ; Base64 encode: 32 bytes → ~44 chars
    xor r10, r10  ; input offset
    xor r11, r11  ; output offset
    lea r14, [rel buf_read]   ; source
    lea r15, [rel b64_alpha]  ; alphabet
    lea r9, [rel buf_b64]     ; dest

.b64_loop_gp:
    cmp r10, r13
    jge .b64_done_gp

    ; Get 3 bytes
    movzx eax, byte [r14+r10]
    shl eax, 16

    mov rcx, r10
    inc rcx
    cmp rcx, r13
    jge .b64_pad2_gp
    movzx edx, byte [r14+rcx]
    shl edx, 8
    or eax, edx

    mov rcx, r10
    add rcx, 2
    cmp rcx, r13
    jge .b64_pad1_gp
    movzx edx, byte [r14+rcx]
    or eax, edx

    ; Extract 4 6-bit values
    mov ecx, eax
    shr ecx, 18
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    shr ecx, 12
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    shr ecx, 6
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    add r10, 3
    jmp .b64_loop_gp

.b64_pad1_gp:
    ; 2 bytes, 3 base64 chars + 1 padding
    mov ecx, eax
    shr ecx, 18
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    shr ecx, 12
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    shr ecx, 6
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov byte [r9+r11], '='
    inc r11
    jmp .b64_done_gp

.b64_pad2_gp:
    ; 1 byte, 2 base64 chars + 2 padding
    mov ecx, eax
    shr ecx, 18
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov ecx, eax
    shr ecx, 12
    and ecx, 0x3F
    mov cl, [r15+rcx]
    mov [r9+r11], cl
    inc r11

    mov byte [r9+r11], '='
    inc r11
    mov byte [r9+r11+1], '='
    inc r11

.b64_done_gp:
    mov byte [r9+r11], 0
    lea rax, [rel buf_b64]
    jmp .gp_done
    
.gp_fail:
    lea rdi, [rel err_init_fail]
    call die
    
.gp_done:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; choose_pass: prompts user → rax=ptr to passphrase
choose_pass:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    
    ; Show choices
    lea rdi, [rel msg_choice1]
    call print_str_stderr
    lea rdi, [rel msg_choice2]
    call print_str_stderr
    lea rdi, [rel msg_choice_q]
    call print_str_stderr
    
    ; Read 1 char
    mov rdi, STDIN
    lea rsi, [rel buf_read]
    mov rdx, 2
    mov rax, SYS_READ
    syscall
    
    mov al, [rel buf_read]
    cmp al, '1'
    je .cp_gen
    cmp al, '2'
    je .cp_manual
    cmp al, 10
    je .cp_manual  ; treat empty as manual
    
    lea rdi, [rel err_pass_in]
    call die
    
.cp_gen:
    ; Skip newline
    mov rdi, STDIN
    lea rsi, [rel buf_read]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    
    call generate_pass
    
    ; Print it
    lea rdi, [rel msg_gen_hdr]
    call print_str_stderr
    mov rdi, rax
    call print_str_stderr
    lea rdi, [rel msg_gen_ftr]
    call print_str_stderr
    jmp .cp_done
    
.cp_manual:
    ; Skip newline if any
    mov rdi, STDIN
    lea rsi, [rel buf_read]
    mov rdx, 1
    mov rax, SYS_READ
    syscall
    
    call read_pass
    jmp .cp_done
    
.cp_done:
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; COMMANDS
; ──────────────────────────────────────────────────────────

; cmd_init: Create encrypted volume and store passphrase
cmd_init:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14

    ; Check already initialized
    lea rdi, [rel final_cipher]
    call is_initialized
    test rax, rax
    jnz .ci_already

    ; Choose passphrase
    call choose_pass
    mov r12, rax  ; passphrase pointer

    ; Get length
    mov rdi, r12
    call my_strlen
    mov r13, rax  ; length

    ; Create cipher dir: mkdir -p cipher_dir
    lea r8, [rel exec_argv]
    lea r9, [rel bin_mkdir]
    mov [r8], r9
    lea r9, [rel mkdir_p]
    mov [r8+8], r9
    lea r9, [rel final_cipher]
    mov [r8+16], r9
    mov qword [r8+24], 0

    mov rdi, r8
    call run_simple
    test rax, rax
    jnz .ci_init_fail

    ; Run gocryptfs -init -q -- cipher_dir
    lea r8, [rel exec_argv]
    lea r9, [rel bin_gocryptfs]
    mov [r8], r9
    lea r9, [rel gfs_q]
    mov [r8+8], r9
    lea r9, [rel gfs_init]
    mov [r8+16], r9
    lea r9, [rel gfs_dd]
    mov [r8+24], r9
    lea r9, [rel final_cipher]
    mov [r8+32], r9
    mov qword [r8+40], 0

    mov rdi, r8
    mov rsi, r12
    mov rdx, r13
    call run_with_stdin
    test rax, rax
    jnz .ci_init_fail

    ; Store passphrase in keyring
    mov rdi, r12
    lea rsi, [rel final_plain]
    call kr_store

    ; Print success
    lea rdi, [rel msg_init_ok]
    call print_str_stderr
    jmp .ci_done

.ci_already:
    lea rdi, [rel err_already]
    call print_str_stderr
    lea rdi, [rel final_cipher]
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit

.ci_init_fail:
    lea rdi, [rel err_init_fail]
    call die

.ci_done:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; cmd_open: Mount vault using passphrase from keyring
cmd_open:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14

    ; Recover stale mount
    lea rdi, [rel final_plain]
    call recover_stale

    ; Check already mounted
    lea rdi, [rel final_plain]
    call is_mounted
    test rax, rax
    jnz .co_already

    ; Check initialized
    lea rdi, [rel final_cipher]
    call is_initialized
    test rax, rax
    jz .co_not_init

    ; Lookup passphrase
    lea rdi, [rel final_plain]
    call kr_lookup
    test rax, rax
    jz .co_keyring_fail
    mov r12, rax  ; passphrase
    mov rdi, rax
    call my_strlen
    mov r13, rax  ; length

    ; Create plain dir: mkdir -p plain_dir
    lea r8, [rel exec_argv]
    lea r9, [rel bin_mkdir]
    mov [r8], r9
    lea r9, [rel mkdir_p]
    mov [r8+8], r9
    lea r9, [rel final_plain]
    mov [r8+16], r9
    mov qword [r8+24], 0

    mov rdi, r8
    call run_simple
    test rax, rax
    jnz .co_mount_fail

    ; Mount: gocryptfs -q -- cipher_dir plain_dir
    lea r8, [rel exec_argv]
    lea r9, [rel bin_gocryptfs]
    mov [r8], r9
    lea r9, [rel gfs_q]
    mov [r8+8], r9
    lea r9, [rel gfs_dd]
    mov [r8+16], r9
    lea r9, [rel final_cipher]
    mov [r8+24], r9
    lea r9, [rel final_plain]
    mov [r8+32], r9
    mov qword [r8+40], 0

    mov rdi, r8
    mov rsi, r12
    mov rdx, r13
    call run_with_stdin
    test rax, rax
    jnz .co_mount_fail

    jmp .co_done

.co_already:
    lea rdi, [rel msg_open]
    call print_str_stderr
    jmp .co_done

.co_not_init:
    lea rdi, [rel err_not_init_c]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit

.co_keyring_fail:
    lea rdi, [rel err_keyring]
    call die

.co_mount_fail:
    lea rdi, [rel err_mount_fail]
    call die

.co_done:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; cmd_close: Unmount vault
cmd_close:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9

    ; Check stale
    lea rdi, [rel final_plain]
    call is_stale
    test rax, rax
    jz .cc_not_stale

    ; Force unmount stale mount
    lea r8, [rel exec_argv]
    lea r9, [rel bin_fusermount]
    mov [r8], r9
    lea r9, [rel fm_uz]
    mov [r8+8], r9
    mov [r8+16], rdi
    mov qword [r8+24], 0

    mov rdi, r8
    call run_simple
    test rax, rax
    jz .cc_done
    lea rdi, [rel err_umount_fail]
    call die

.cc_not_stale:
    ; Check mounted
    lea rdi, [rel final_plain]
    call is_mounted
    test rax, rax
    jz .cc_done

    ; Unmount
    lea r8, [rel exec_argv]
    lea r9, [rel bin_fusermount]
    mov [r8], r9
    lea r9, [rel fm_u]
    mov [r8+8], r9
    mov [r8+16], rdi
    mov qword [r8+24], 0

    mov rdi, r8
    call run_simple
    test rax, rax
    jz .cc_done
    lea rdi, [rel err_umount_fail]
    call die

.cc_done:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; cmd_status: Print state
cmd_status:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi

    ; Check initialized
    lea rdi, [rel final_cipher]
    call is_initialized
    test rax, rax
    jz .cs_not_init

    ; Check stale
    lea rdi, [rel final_plain]
    call is_stale
    test rax, rax
    jnz .cs_stale

    ; Check mounted
    lea rdi, [rel final_plain]
    call is_mounted
    test rax, rax
    jnz .cs_open

    ; Locked (initialized but not mounted)
    lea rdi, [rel msg_locked]
    jmp .cs_print

.cs_stale:
    lea rdi, [rel msg_stale]
    jmp .cs_print

.cs_open:
    lea rdi, [rel msg_open]
    jmp .cs_print

.cs_not_init:
    lea rdi, [rel msg_not_init]
    ; fall through

.cs_print:
    push rdi
    call my_strlen
    mov rdx, rax
    pop rsi
    mov rdi, STDOUT
    mov rax, SYS_WRITE
    syscall

    ; Print newline
    lea rdi, [rel nl]
    call print_str_stdout

    pop rsi
    pop rdi
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; CONFIG LOADING
; ──────────────────────────────────────────────────────────

; load_config: rdi=path
load_config:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    
    ; Open file
    mov rsi, O_RDONLY
    xor rdx, rdx
    mov rax, SYS_OPEN
    syscall
    test rax, rax
    js .lc_done
    mov r12, rax  ; fd
    
    ; Read file
.lc_read:
    mov rdi, r12
    lea rsi, [rel buf_read]
    mov rdx, BUF_SIZE
    mov rax, SYS_READ
    syscall
    test rax, rax
    jle .lc_close
    mov r8, rax   ; bytes read
    
    ; Process byte by byte to find lines
    xor r9, r9    ; line start offset
    
.lc_parse:
    cmp r9, r8
    jge .lc_read
    
    ; Find end of line
    mov r10, r9
.lc_find_eol:
    cmp r10, r8
    jge .lc_process_line
    lea rdi, [rel buf_read]
    mov al, [rdi+r10]
    cmp al, 10
    je .lc_process_line
    inc r10
    jmp .lc_find_eol

.lc_process_line:
    ; Copy line to buf_line
    mov rcx, r10
    sub rcx, r9
    lea rdi, [rel buf_line]
    lea rsi, [rel buf_read]
    add rsi, r9
    
    ; Check if line starts with PLAIN_DIR= or CIPHER_DIR=
    push rcx
    lea rdi, [rel buf_line]
    lea rsi, [rel key_plain]
    call my_strcmp
    pop rcx
    test rax, rax
    je .lc_found_plain
    
    push rcx
    lea rdi, [rel buf_line]
    lea rsi, [rel key_cipher]
    call my_strcmp
    pop rcx
    test rax, rax
    je .lc_found_cipher
    
    ; Unknown key or empty line - skip
    mov r9, r10
    inc r9
    jmp .lc_parse
    
.lc_found_plain:
    ; Skip "PLAIN_DIR=" (10 chars)
    add r9, 10
    mov rcx, r10
    sub rcx, r9
    ; Copy value
    lea rdi, [rel conf_plain]
    lea rsi, [rel buf_line]
    add rsi, 10
    call my_strcpy
    jmp .lc_next

.lc_found_cipher:
    ; Skip "CIPHER_DIR=" (11 chars)
    add r9, 11
    lea rdi, [rel conf_cipher]
    lea rsi, [rel buf_line]
    add rsi, 11
    call my_strcpy
    mov byte [rel has_cipher], 1
    jmp .lc_next
    
.lc_next:
    mov r9, r10
    inc r9
    jmp .lc_parse
    
.lc_close:
    mov rdi, r12
    call sys_close
    
.lc_done:
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; PATH FINALIZATION
; ──────────────────────────────────────────────────────────

; cmd_passwd: Rotate gocryptfs passphrase
cmd_passwd:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11
    push r12
    push r13
    push r14

    ; Check initialized
    lea rdi, [rel final_cipher]
    call is_initialized
    test rax, rax
    jz .cp_not_init

    ; Lookup old passphrase
    lea rdi, [rel final_plain]
    call kr_lookup
    test rax, rax
    jz .cp_no_current
    mov r12, rax  ; old pass

    ; Get new passphrase
    call choose_pass
    mov r13, rax  ; new pass

    ; Get new pass length
    mov rdi, r13
    call my_strlen
    mov r14, rax

    ; Build stdin: old_pass\nnew_pass\n
    ; Copy old pass to buf_read
    lea rdi, [rel buf_read]
    mov rsi, r12
    call my_strcpy

    ; Get old pass length
    mov rdi, r12
    call my_strlen
    mov r10, rax

    ; Add newline after old pass
    lea rdi, [rel buf_read]
    mov byte [rdi+r10], 10
    inc r10  ; r10 = old_len + 1

    ; Copy new pass after old_pass\n
    lea rsi, [rel buf_read]
    add rsi, r10
    mov rdi, rsi
    mov rsi, r13
    call my_strcpy

    ; Add newline after new pass
    mov rdi, rsi
    call my_strlen
    mov byte [rsi+rax], 10
    inc rax

    ; Total stdin length: old_len + 1 + new_len + 1
    mov rdi, r12
    call my_strlen
    mov r11, rax
    add r11, 1  ; + newline
    mov rdi, r13
    call my_strlen
    add r11, rax
    add r11, 1  ; + newline
    mov r10, r11  ; total stdin length

    ; Run gocryptfs -passwd -q -- cipher_dir
    lea r8, [rel exec_argv]
    lea r9, [rel bin_gocryptfs]
    mov [r8], r9
    lea r9, [rel gfs_q]
    mov [r8+8], r9
    lea r9, [rel gfs_passwd]
    mov [r8+16], r9
    lea r9, [rel gfs_dd]
    mov [r8+24], r9
    lea r9, [rel final_cipher]
    mov [r8+32], r9
    mov qword [r8+40], 0

    mov rdi, r8
    lea rsi, [rel buf_read]
    mov rdx, r10
    call run_with_stdin
    test rax, rax
    jnz .cp_passwd_fail

    ; Store new passphrase
    mov rdi, r13
    lea rsi, [rel final_plain]
    call kr_store

    lea rdi, [rel msg_passwd_ok]
    call print_str_stderr
    jmp .cp_done

.cp_not_init:
    lea rdi, [rel err_not_init_c]
    call die

.cp_no_current:
    lea rdi, [rel err_no_current]
    call die

.cp_passwd_fail:
    lea rdi, [rel err_passwd_fail]
    call die

.cp_done:
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop r9
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; finalize_dirs: Construct final paths
finalize_dirs:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rdx

    ; Copy home_dir to final_plain
    lea rsi, [rel home_dir]
    lea rdi, [rel final_plain]
    call my_strcpy
    
    ; Append "/keys"
    lea rdi, [rel final_plain]
    call my_strlen
    lea rdi, [rel final_plain]
    add rdi, rax
    lea rsi, [rel default_plain]  ; "/keys"
    call my_strcpy
    
    ; Build cipher dir: home_dir + "/.keys.enc"
    lea rsi, [rel home_dir]
    lea rdi, [rel final_cipher]
    call my_strcpy
    
    ; Append "/.keys.enc"
    lea rdi, [rel final_cipher]
    call my_strlen
    lea rdi, [rel final_cipher]
    add rdi, rax
    ; Manually write "/.keys.enc"
    mov byte [rdi], '/'
    mov byte [rdi+1], '.'
    mov byte [rdi+2], 'k'
    mov byte [rdi+3], 'e'
    mov byte [rdi+4], 'y'
    mov byte [rdi+5], 's'
    mov byte [rdi+6], '.'
    mov byte [rdi+7], 'e'
    mov byte [rdi+8], 'n'
    mov byte [rdi+9], 'c'
    mov byte [rdi+10], 0

    pop rdx
    pop rsi
    pop rdi
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; HOME DIR DETECTION
; ──────────────────────────────────────────────────────────

get_home_dir:
    push rbp
    mov rbp, rsp
    push rdi
    push rsi
    push rcx
    push rdx
    push r8
    push r9
    
    ; Iterate environ to find HOME=
    mov r8, [rel envp_global]
    
.ghd_loop_ghd:
    mov rsi, [r8]
    test rsi, rsi
    jz .ghd_fallback_ghd
    
    ; Check if starts with "HOME="
    cmp dword [rsi], 'EMOH'  ; "HOME" in little-endian
    jne .ghd_next_ghd
    cmp byte [rsi+4], '='
    je .ghd_found_ghd
    
.ghd_next_ghd:
    add r8, 8
    jmp .ghd_loop_ghd
    
.ghd_found_ghd:
    add rsi, 5  ; skip "HOME="
    lea rdi, [rel home_dir]
    call my_strcpy
    jmp .ghd_done_ghd
    
.ghd_fallback_ghd:
    ; Fallback: try to use /proc/self/environ or default
    ; For now, set to empty
    mov byte [rel home_dir], 0
    
.ghd_done_ghd:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rsi
    pop rdi
    pop rbp
    ret

; ──────────────────────────────────────────────────────────
; MAIN ENTRY POINT
; ──────────────────────────────────────────────────────────

_start:
    ; Initialize
    xor rax, rax
    mov byte [rel has_cipher], 0

    ; Get HOME - iterate envp from stack
    ; Stack: [argc][argv...][NULL][envp...][NULL]
    pop rcx             ; argc
    mov r11, rcx        ; Save argc in r11
    mov r12, rsp        ; Save stack AFTER popping argc
    ; Skip argv (argc * 8 bytes)
    shl rcx, 3
    add rsp, rcx
    pop rax             ; Skip NULL
    mov r13, rsp        ; r13 = envp
    
    ; Find HOME in envp
.find_home_start:
    mov rsi, [r13]
    test rsi, rsi
    jz .no_home
    cmp dword [rsi], 'EMOH'
    jne .next_env
    cmp byte [rsi+4], '='
    je .found_home
.next_env:
    add r13, 8
    jmp .find_home_start
    
.found_home:
    add rsi, 5
    ; Manually copy HOME string without calling function
    lea rdi, [rel home_dir]
.copy_home:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .got_home
    inc rsi
    inc rdi
    jmp .copy_home
    
.no_home:
    mov byte [rel home_dir], 0
    
.got_home:
    ; Restore stack
    mov rsp, r12
    
    ; Load system config
    lea rdi, [rel conf_sys]
    call load_config
    
    ; Parse CLI arguments
    mov rcx, r11        ; Restore argc
    mov r12, rsp        ; argv pointer
    xor r13, r13      ; arg index
    xor r14, r14      ; command set flag
    
start_arg_loop:
    cmp r13, rcx
    jge start_arg_done
    inc r13
    
    mov rdi, [r12+r13*8]
    test rdi, rdi
    jz start_arg_done
    
    ; Check if it's an option (starts with -)
    mov al, [rdi]
    cmp al, '-'
    je start_parse_option
    
    ; It's a command
    test r14, r14
    jnz start_unexpected_arg
    mov r14, 1
    mov rsi, rdi          ; rsi = command string (argv[i])
    lea rdi, [rel cmd_str]  ; rdi = destination
    call my_strcpy
    jmp start_arg_loop
    
start_parse_option:
    ; Check --dir=
    cmp byte [rdi+1], '-'
    jne start_check_help
    cmp byte [rdi+2], 'd'
    jne start_check_cipher_opt
    cmp byte [rdi+3], 'i'
    jne start_check_cipher_opt
    cmp byte [rdi+4], 'r'
    jne start_check_cipher_opt
    cmp byte [rdi+5], '='
    je start_opt_dir_eq
    cmp byte [rdi+5], 0
    je start_opt_dir
    jmp start_unknown_opt
    
start_opt_dir_eq:
    add rdi, 6
    lea rsi, [rel arg_plain]
    call my_strcpy
    jmp start_arg_loop
    
start_opt_dir:
    inc r13
    mov rdi, [r12+r13*8]
    test rdi, rdi
    jz start_dir_required
    lea rsi, [rel arg_plain]
    call my_strcpy
    jmp start_arg_loop
    
start_check_cipher_opt:
    ; Check --cipher-dir=
    cmp byte [rdi+2], 'c'
    jne start_check_version
    cmp byte [rdi+3], 'i'
    jne start_check_version
    cmp byte [rdi+4], 'p'
    jne start_check_version
    cmp byte [rdi+5], 'h'
    jne start_check_version
    cmp byte [rdi+6], 'e'
    jne start_check_version
    cmp byte [rdi+7], 'r'
    jne start_check_version
    cmp byte [rdi+8], '-'
    jne start_check_version
    cmp byte [rdi+9], 'd'
    jne start_check_version
    cmp byte [rdi+10], 'i'
    jne start_check_version
    cmp byte [rdi+11], 'r'
    jne start_check_version
    cmp byte [rdi+12], '='
    je start_opt_cipher_eq
    cmp byte [rdi+12], 0
    je start_opt_cipher
    jmp start_check_version
    
start_opt_cipher_eq:
    add rdi, 13
    lea rsi, [rel arg_cipher]
    call my_strcpy
    mov byte [rel has_cipher], 1
    jmp start_arg_loop
    
start_opt_cipher:
    inc r13
    mov rdi, [r12+r13*8]
    test rdi, rdi
    jz start_cipher_required
    lea rsi, [rel arg_cipher]
    call my_strcpy
    mov byte [rel has_cipher], 1
    jmp start_arg_loop
    
start_check_version:
    ; Check --version
    cmp byte [rdi+2], 'v'
    jne start_check_help
    cmp byte [rdi+3], 'e'
    jne start_check_help
    cmp byte [rdi+4], 'r'
    jne start_check_help
    cmp byte [rdi+5], 's'
    jne start_check_help
    cmp byte [rdi+6], 'i'
    jne start_check_help
    cmp byte [rdi+7], 'o'
    jne start_check_help
    cmp byte [rdi+8], 'n'
    jne start_check_help
    cmp byte [rdi+9], 0
    jne start_check_help
    
    lea rdi, [rel version_str]
    ; Inline print to avoid register issues
    push rdi
    call my_strlen
    mov rdx, rax
    pop rsi
    mov rdi, STDOUT
    mov rax, SYS_WRITE
    syscall
    mov rdi, EXIT_SUCCESS
    call sys_exit
    
start_check_help:
    ; Check -h or --help
    cmp byte [rdi+1], 'h'
    je start_opt_help
    cmp byte [rdi+1], '-'
    jne start_unknown_opt
    cmp byte [rdi+2], 'h'
    jne start_unknown_opt
    cmp byte [rdi+3], 'e'
    jne start_unknown_opt
    cmp byte [rdi+4], 'l'
    jne start_unknown_opt
    cmp byte [rdi+5], 'p'
    jne start_unknown_opt
    cmp byte [rdi+6], 0
    jne start_unknown_opt
    
start_opt_help:
    lea rdi, [rel usage_text]
    call print_str_stdout
    mov rdi, EXIT_SUCCESS
    call sys_exit
    
start_unknown_opt:
    lea rdi, [rel err_unk_opt]
    call print_str_stderr
    mov rdi, [r12+r13*8]
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit
    
start_unexpected_arg:
    lea rdi, [rel err_unexp_arg]
    call print_str_stderr
    mov rdi, [r12+r13*8]
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit
    
start_dir_required:
    lea rdi, [rel err_dir_req]
    call die
    
start_cipher_required:
    lea rdi, [rel err_cipher_req]
    call die
    
start_arg_done:
    ; Finalize paths
    call finalize_dirs
    
    ; Execute command - minimal dispatch
    test r14, r14
    jz start_no_cmd

    ; Check cmd_str against known commands
    lea rdi, [rel cmd_str]
    lea rsi, [rel cmd_init_s]
    call my_strcmp
    test rax, rax
    je start_do_init

    lea rdi, [rel cmd_str]
    lea rsi, [rel cmd_open_s]
    call my_strcmp
    test rax, rax
    je start_do_open

    lea rdi, [rel cmd_str]
    lea rsi, [rel cmd_close_s]
    call my_strcmp
    test rax, rax
    je start_do_close

    lea rdi, [rel cmd_str]
    lea rsi, [rel cmd_status_s]
    call my_strcmp
    test rax, rax
    je start_do_status

    lea rdi, [rel cmd_str]
    lea rsi, [rel cmd_passwd_s]
    call my_strcmp
    test rax, rax
    je start_do_passwd

    ; Unknown command
    lea rdi, [rel err_unk_cmd]
    call print_str_stderr
    lea rdi, [rel cmd_str]
    call print_str_stderr
    lea rdi, [rel nl]
    call print_str_stderr
    mov rdi, EXIT_FAILURE
    call sys_exit

start_do_init:
    call cmd_init
    jmp start_exit_success

start_do_open:
    call cmd_open
    jmp start_exit_success

start_do_close:
    call cmd_close
    jmp start_exit_success

start_do_status:
    call cmd_status
    jmp start_exit_success

start_do_passwd:
    call cmd_passwd
    jmp start_exit_success

start_no_cmd:
    lea rdi, [rel usage_text]
    call print_str_stderr
    mov rdi, EXIT_SUCCESS
    call sys_exit

start_exit_success:
    mov rdi, EXIT_SUCCESS
    call sys_exit

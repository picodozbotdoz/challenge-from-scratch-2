# gen/app_gen.s — EMITTED by spec/EmitAsm.lean (lake exe derive). Do not hand-edit.
# Layout equates: owned here, pinned by runtime/abi.h _Static_asserts.
.intel_syntax noprefix
.set APPREQ_METHOD, 0
.set APPREQ_PATH_LEN, 4
.set APPREQ_PATH, 8
.set APPREQ_AUTH_LEN, 16
.set APPREQ_AUTH, 24
.set APPREQ_BODY_LEN, 32
.set APPREQ_BODY, 40
.set OUTBUF_BASE, 0
.set OUTBUF_LEN, 8
.set OUTBUF_CAP, 16
.text
.Lstreq:
    cmp rsi, rcx
    jne .Lstreq_no
.Lstreq_loop:
    test rcx, rcx
    jz .Lstreq_yes
    movzx r8d, BYTE PTR [rdi]
    movzx r9d, BYTE PTR [rdx]
    cmp r8b, r9b
    jne .Lstreq_no
    inc rdi
    inc rdx
    dec rcx
    jmp .Lstreq_loop
.Lstreq_yes:
    mov al, 1
    ret
.Lstreq_no:
    xor eax, eax
    ret
.Lstreqpfx:
    cmp rsi, rcx
    jb .Lstreqpfx_no
.Lstreqpfx_loop:
    test rcx, rcx
    jz .Lstreqpfx_yes
    movzx r8d, BYTE PTR [rdi]
    movzx r9d, BYTE PTR [rdx]
    cmp r8b, r9b
    jne .Lstreqpfx_no
    inc rdi
    inc rdx
    dec rcx
    jmp .Lstreqpfx_loop
.Lstreqpfx_yes:
    mov al, 1
    ret
.Lstreqpfx_no:
    xor eax, eax
    ret
.Lhas_slash:
    xor eax, eax
    xor rcx, rcx
.Lhas_slash_loop:
    cmp rcx, rsi
    jae .Lhas_slash_done
    cmp BYTE PTR [rdi+rcx], 47
    je .Lhas_slash_yes
    inc rcx
    jmp .Lhas_slash_loop
.Lhas_slash_yes:
    mov al, 1
    ret
.Lhas_slash_done:
    xor eax, eax
    ret
.Lparseid:
    test rsi, rsi
    jz .Lparseid_bad
    xor eax, eax
    xor rcx, rcx
.Lparseid_loop:
    cmp rcx, rsi
    jae .Lparseid_done
    movzx r8d, BYTE PTR [rdi+rcx]
    sub r8d, 48
    cmp r8d, 9
    ja .Lparseid_bad
    imul rax, rax, 10
    jo .Lparseid_bad
    add rax, r8
    jo .Lparseid_bad
    inc rcx
    jmp .Lparseid_loop
.Lparseid_done:
    test rax, rax
    jz .Lparseid_bad
    mov edx, 1
    ret
.Lparseid_bad:
    xor eax, eax
    xor edx, edx
    ret
.Lstrlen:
    xor eax, eax
.Lstrlen_loop:
    cmp BYTE PTR [rdi+rax], 0
    je .Lstrlen_done
    inc rax
    jmp .Lstrlen_loop
.Lstrlen_done:
    ret
.globl app_init
app_init:
    xor eax, eax
    ret
.globl app_request
app_request:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov eax, [rbx+APPREQ_METHOD]
    cmp eax, 0
    je .Lroute_get
    cmp eax, 1
    je .Lroute_post
    jmp .Lnotfound
.Lroute_get:
    mov rdi, [rbx+APPREQ_PATH]
    mov esi, [rbx+APPREQ_PATH_LEN]
    lea rdx, [rip+.Lstr0]
    mov ecx, 7
    call .Lstreq
    test al, al
    jnz .Lhealth
    mov rdi, [rbx+APPREQ_PATH]
    mov esi, [rbx+APPREQ_PATH_LEN]
    lea rdx, [rip+.Lstr1]
    mov ecx, 5
    call .Lstreq
    test al, al
    jnz .Lfeed
    mov rdi, [rbx+APPREQ_PATH]
    mov esi, [rbx+APPREQ_PATH_LEN]
    lea rdx, [rip+.Lstr2]
    mov ecx, 7
    call .Lstreqpfx
    test al, al
    jz .Lnotfound
    mov rdi, [rbx+APPREQ_PATH]
    add rdi, 7
    mov esi, [rbx+APPREQ_PATH_LEN]
    sub esi, 7
    call .Lhas_slash
    test al, al
    jnz .Lnotfound
    mov rdi, [rbx+APPREQ_PATH]
    add rdi, 7
    mov esi, [rbx+APPREQ_PATH_LEN]
    sub esi, 7
    call .Lparseid
    test edx, edx
    jz .Linvalidid
    jmp .Lgetpost
.Lroute_post:
    jmp .Lpost
.Lnotfound:
    mov rdi, r12
    lea rsi, [rip+.Lstr3]
    mov edx, 21
    call x_out_str
    mov eax, 404
    jmp .Ldone
.Linvalidid:
    mov rdi, r12
    lea rsi, [rip+.Lstr4]
    mov edx, 27
    call x_out_str
    mov eax, 400
    jmp .Ldone
.Ldone:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.Lhealth:
    lea rdi, [rip+.Lstr5]
    mov esi, 8
    call x_db_prepare
    test rax, rax
    jz .Lhealth_bad
    mov r13, rax
    mov rdi, r13
    call x_db_step
    cmp eax, 1
    jne .Lhealth_bad_reset
    mov rdi, r13
    call x_db_reset
    mov rdi, r12
    lea rsi, [rip+.Lstr6]
    mov edx, 36
    call x_out_str
    mov rdi, r12
    call x_uptime
    mov rdi, r12
    mov rsi, rax
    call x_out_int
    mov rdi, r12
    mov esi, 125
    call x_out_byte
    mov eax, 200
    jmp .Ldone
.Lhealth_bad_reset:
    mov rdi, r13
    call x_db_reset
.Lhealth_bad:
    mov rdi, r12
    lea rsi, [rip+.Lstr7]
    mov edx, 48
    call x_out_str
    call x_db_errmsg
    mov r14, rax
    mov rdi, r14
    call .Lstrlen
    mov rdx, rax
    mov rsi, r14
    mov rdi, r12
    call x_out_json_escaped_str
    mov rdi, r12
    mov esi, 34
    call x_out_byte
    mov rdi, r12
    mov esi, 125
    call x_out_byte
    mov eax, 503
    jmp .Ldone
.Lfeed:
    mov rdi, r12
    call x_fail
    jmp .Ldone
.Lgetpost:
    mov rdi, r12
    call x_fail
    jmp .Ldone
.Lpost:
    mov rdi, r12
    call x_fail
    jmp .Ldone
.section .rodata
.Lstr0:
    .byte 47, 104, 101, 97, 108, 116, 104
.Lstr1:
    .byte 47, 102, 101, 101, 100
.Lstr2:
    .byte 47, 112, 111, 115, 116, 115, 47
.Lstr3:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 110, 111, 116, 32, 102, 111, 117, 110, 100, 34, 125
.Lstr4:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 105, 110, 118, 97, 108, 105, 100, 32, 112, 111, 115, 116, 32, 105, 100, 34, 125
.Lstr5:
    .byte 83, 69, 76, 69, 67, 84, 32, 49
.Lstr6:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 111, 107, 34, 44, 34, 100, 98, 34, 58, 34, 111, 107, 34, 44, 34, 117, 112, 116, 105, 109, 101, 95, 115, 34, 58
.Lstr7:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 100, 101, 103, 114, 97, 100, 101, 100, 34, 44, 34, 100, 98, 34, 58, 34, 117, 110, 114, 101, 97, 99, 104, 97, 98, 108, 101, 34, 44, 34, 101, 114, 114, 111, 114, 34, 58

.section .note.GNU-stack,"",@progbits

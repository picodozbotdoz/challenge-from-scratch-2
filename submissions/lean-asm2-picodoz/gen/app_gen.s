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
.Lerr500:
    mov rdi, r12
    call x_fail
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
.Lemit_post:
    sub rsp, 8
    mov rdi, r12
    lea rsi, [rip+.Lstr5]
    mov edx, 6
    call x_out_str
    mov rdi, r13
    xor esi, esi
    call x_db_column_int
    mov rdi, r12
    mov rsi, rax
    call x_out_int
    mov rdi, r12
    lea rsi, [rip+.Lstr6]
    mov edx, 9
    call x_out_str
    mov rdi, r13
    mov esi, 1
    call x_db_column_bytes
    mov r14, rax
    mov rdi, r13
    mov esi, 1
    call x_db_column_text
    mov rsi, rax
    mov rdx, r14
    mov rdi, r12
    call x_out_json_escaped_str
    mov rdi, r12
    lea rsi, [rip+.Lstr7]
    mov edx, 16
    call x_out_str
    mov rdi, r13
    mov esi, 2
    call x_db_column_bytes
    mov r14, rax
    mov rdi, r13
    mov esi, 2
    call x_db_column_text
    mov rsi, rax
    mov rdx, r14
    mov rdi, r12
    call x_out_json_escaped_str
    mov rdi, r12
    lea rsi, [rip+.Lstr8]
    mov edx, 12
    call x_out_str
    mov rdi, r13
    mov esi, 3
    call x_db_column_bytes
    mov r14, rax
    mov rdi, r13
    mov esi, 3
    call x_db_column_text
    mov rsi, rax
    mov rdx, r14
    mov rdi, r12
    call x_out_json_escaped_str
    mov rdi, r12
    lea rsi, [rip+.Lstr9]
    mov edx, 15
    call x_out_str
    mov rdi, r13
    mov esi, 4
    call x_db_column_int
    mov rdi, r12
    mov rsi, rax
    call x_out_int
    mov rdi, r12
    mov esi, 125
    call x_out_byte
    add rsp, 8
    ret
.Lhealth:
    lea rdi, [rip+.Lstr10]
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
    lea rsi, [rip+.Lstr11]
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
    lea rsi, [rip+.Lstr12]
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
    lea rdi, [rip+.Lstr13]
    mov esi, 207
    call x_db_prepare
    test rax, rax
    jz .Lerr500
    mov r13, rax
    mov rdi, r12
    lea rsi, [rip+.Lstr14]
    mov edx, 10
    call x_out_str
    xor r15d, r15d
.Lfeed_loop:
    cmp r15d, 20
    jae .Lfeed_end
    mov rdi, r13
    call x_db_step
    cmp eax, 1
    jne .Lfeed_end
    test r15d, r15d
    jz .Lfeed_first
    mov rdi, r12
    mov esi, 44
    call x_out_byte
.Lfeed_first:
    call .Lemit_post
    inc r15d
    jmp .Lfeed_loop
.Lfeed_end:
    mov rdi, r12
    lea rsi, [rip+.Lstr15]
    mov edx, 2
    call x_out_str
    mov rdi, r13
    call x_db_reset
    mov eax, 200
    jmp .Ldone
.Lgetpost:
    mov r14, rax
    lea rdi, [rip+.Lstr16]
    mov esi, 175
    call x_db_prepare
    test rax, rax
    jz .Lerr500
    mov r13, rax
    mov rdi, r13
    mov esi, 1
    mov rdx, r14
    call x_db_bind_int
    mov rdi, r13
    call x_db_step
    cmp eax, 1
    jne .Lgetpost_notfound
    mov rdi, r12
    lea rsi, [rip+.Lstr17]
    mov edx, 8
    call x_out_str
    call .Lemit_post
    mov rdi, r12
    mov esi, 125
    call x_out_byte
    mov rdi, r13
    call x_db_reset
    mov eax, 200
    jmp .Ldone
.Lgetpost_notfound:
    mov rdi, r13
    call x_db_reset
    mov rdi, r12
    lea rsi, [rip+.Lstr18]
    mov edx, 26
    call x_out_str
    mov eax, 404
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
    .byte 123, 34, 105, 100, 34, 58
.Lstr6:
    .byte 44, 34, 98, 111, 100, 121, 34, 58, 34
.Lstr7:
    .byte 34, 44, 34, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 34, 58, 34
.Lstr8:
    .byte 34, 44, 34, 97, 117, 116, 104, 111, 114, 34, 58, 34
.Lstr9:
    .byte 34, 44, 34, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 34, 58
.Lstr10:
    .byte 83, 69, 76, 69, 67, 84, 32, 49
.Lstr11:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 111, 107, 34, 44, 34, 100, 98, 34, 58, 34, 111, 107, 34, 44, 34, 117, 112, 116, 105, 109, 101, 95, 115, 34, 58
.Lstr12:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 100, 101, 103, 114, 97, 100, 101, 100, 34, 44, 34, 100, 98, 34, 58, 34, 117, 110, 114, 101, 97, 99, 104, 97, 98, 108, 101, 34, 44, 34, 101, 114, 114, 111, 114, 34, 58
.Lstr13:
    .byte 83, 69, 76, 69, 67, 84, 32, 112, 46, 105, 100, 44, 32, 112, 46, 98, 111, 100, 121, 44, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 44, 32, 117, 46, 117, 115, 101, 114, 110, 97, 109, 101, 44, 32, 40, 83, 69, 76, 69, 67, 84, 32, 99, 111, 117, 110, 116, 40, 42, 41, 32, 70, 82, 79, 77, 32, 108, 105, 107, 101, 115, 32, 108, 32, 87, 72, 69, 82, 69, 32, 108, 46, 112, 111, 115, 116, 95, 105, 100, 32, 61, 32, 112, 46, 105, 100, 41, 32, 65, 83, 32, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 32, 70, 82, 79, 77, 32, 112, 111, 115, 116, 115, 32, 112, 32, 74, 79, 73, 78, 32, 117, 115, 101, 114, 115, 32, 117, 32, 79, 78, 32, 117, 46, 105, 100, 32, 61, 32, 112, 46, 117, 115, 101, 114, 95, 105, 100, 32, 79, 82, 68, 69, 82, 32, 66, 89, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 32, 68, 69, 83, 67, 44, 32, 112, 46, 105, 100, 32, 68, 69, 83, 67, 32, 76, 73, 77, 73, 84, 32, 50, 48
.Lstr14:
    .byte 123, 34, 112, 111, 115, 116, 115, 34, 58, 91
.Lstr15:
    .byte 93, 125
.Lstr16:
    .byte 83, 69, 76, 69, 67, 84, 32, 112, 46, 105, 100, 44, 32, 112, 46, 98, 111, 100, 121, 44, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 44, 32, 117, 46, 117, 115, 101, 114, 110, 97, 109, 101, 44, 32, 40, 83, 69, 76, 69, 67, 84, 32, 99, 111, 117, 110, 116, 40, 42, 41, 32, 70, 82, 79, 77, 32, 108, 105, 107, 101, 115, 32, 108, 32, 87, 72, 69, 82, 69, 32, 108, 46, 112, 111, 115, 116, 95, 105, 100, 32, 61, 32, 112, 46, 105, 100, 41, 32, 65, 83, 32, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 32, 70, 82, 79, 77, 32, 112, 111, 115, 116, 115, 32, 112, 32, 74, 79, 73, 78, 32, 117, 115, 101, 114, 115, 32, 117, 32, 79, 78, 32, 117, 46, 105, 100, 32, 61, 32, 112, 46, 117, 115, 101, 114, 95, 105, 100, 32, 87, 72, 69, 82, 69, 32, 112, 46, 105, 100, 32, 61, 32, 63
.Lstr17:
    .byte 123, 34, 112, 111, 115, 116, 34, 58
.Lstr18:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 112, 111, 115, 116, 32, 110, 111, 116, 32, 102, 111, 117, 110, 100, 34, 125

.section .note.GNU-stack,"",@progbits

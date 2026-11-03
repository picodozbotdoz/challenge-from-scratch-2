# gen/app_gen.s — EMITTED by spec/EmitAsm.lean + spec/EmitAuth.lean (lake exe derive). Do not hand-edit.
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
.globl parseid_asm
parseid_asm:
    test rsi, rsi
    jz parseid_asm_bad
    xor eax, eax
    xor rcx, rcx
parseid_asm_loop:
    cmp rcx, rsi
    jae parseid_asm_done
    movzx r8d, BYTE PTR [rdi+rcx]
    sub r8d, 48
    cmp r8d, 9
    ja parseid_asm_bad
    imul rax, rax, 10
    jo parseid_asm_bad
    add rax, r8
    jo parseid_asm_bad
    inc rcx
    jmp parseid_asm_loop
parseid_asm_done:
    test rax, rax
    jz parseid_asm_bad
    mov edx, 1
    ret
parseid_asm_bad:
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
    sub rsp, 24
    lea rdi, [rsp]
    call x_env_secret
    mov [rip+g_secret_ptr], rax
    mov rax, [rsp]
    mov [rip+g_secret_len], rax
    add rsp, 24
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
    call parseid_asm
    test edx, edx
    jz .Linvalidid
    jmp .Lgetpost
.Lroute_post:
    mov rdi, [rbx+APPREQ_PATH]
    mov esi, [rbx+APPREQ_PATH_LEN]
    lea rdx, [rip+.Lstr3]
    mov ecx, 6
    call .Lstreq
    test al, al
    jnz .Lpost_create
    mov rdi, [rbx+APPREQ_PATH]
    mov esi, [rbx+APPREQ_PATH_LEN]
    lea rdx, [rip+.Lstr2]
    mov ecx, 7
    call .Lstreqpfx
    test al, al
    jz .Lnotfound
    mov rax, [rbx+APPREQ_PATH_LEN]
    sub eax, 7
    cmp eax, 6
    jb .Lnotfound
    mov ecx, eax
    mov rdx, [rbx+APPREQ_PATH]
    lea r8, [rdx+rcx+2]
    mov rdi, r8
    mov esi, 5
    lea rdx, [rip+.Lstr4]
    mov ecx, 5
    call .Lstreq
    test al, al
    jz .Lnotfound
    mov rdi, [rbx+APPREQ_PATH]
    add rdi, 7
    mov rsi, [rbx+APPREQ_PATH_LEN]
    sub esi, 7
    sub esi, 5
    call .Lhas_slash
    test al, al
    jnz .Lnotfound
    mov r14, [rbx+APPREQ_PATH]
    add r14, 7
    mov r15d, [rbx+APPREQ_PATH_LEN]
    sub r15d, 12
    jmp .Lpost_like
.Lnotfound:
    mov rdi, r12
    lea rsi, [rip+.Lstr5]
    mov edx, 21
    call x_out_str
    mov eax, 404
    jmp .Ldone
.Linvalidid:
    mov rdi, r12
    lea rsi, [rip+.Lstr6]
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
.Lhealth:
    lea rdi, [rip+.Lstr7]
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
    lea rsi, [rip+.Lstr8]
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
    lea rsi, [rip+.Lstr9]
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
    lea rdi, [rip+.Lstr10]
    mov esi, 207
    call x_db_prepare
    test rax, rax
    jz .Lerr500
    mov r13, rax
    mov rdi, r12
    lea rsi, [rip+.Lstr11]
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
    lea rsi, [rip+.Lstr12]
    mov edx, 2
    call x_out_str
    mov rdi, r13
    call x_db_reset
    mov eax, 200
    jmp .Ldone
.Lgetpost:
    mov r14, rax
    lea rdi, [rip+.Lstr13]
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
    lea rsi, [rip+.Lstr14]
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
    lea rsi, [rip+.Lstr15]
    mov edx, 26
    call x_out_str
    mov eax, 404
    jmp .Ldone
.Lpost_create:
    call .Lauth_check
    cmp eax, 0
    jne .Lac_err
    mov rdi, r12
    call x_fail
    jmp .Ldone
.Lpost_like:
    call .Lauth_check
    cmp eax, 0
    jne .Lac_err
    mov rdi, r14
    mov rsi, r15
    call parseid_asm
    test edx, edx
    jz .Linvalidid
    mov rdi, r12
    call x_fail
    jmp .Ldone
.Lac_err:
    cmp eax, 1
    jne .Lac_err2
    mov rdi, r12
    lea rsi, [rip+.Lstr16]
    mov edx, 32
    call x_out_str
    mov eax, 401
    jmp .Ldone
.Lac_err2:
    cmp eax, 2
    jne .Lac_err3
    mov rdi, r12
    lea rsi, [rip+.Lstr17]
    mov edx, 36
    call x_out_str
    mov eax, 401
    jmp .Ldone
.Lac_err3:
    mov rdi, r12
    lea rsi, [rip+.Lstr18]
    mov edx, 33
    call x_out_str
    mov eax, 401
    jmp .Ldone
.Lemit_post:
    sub rsp, 8
    mov rdi, r12
    lea rsi, [rip+.Lstr19]
    mov edx, 6
    call x_out_str
    mov rdi, r13
    xor esi, esi
    call x_db_column_int
    mov rdi, r12
    mov rsi, rax
    call x_out_int
    mov rdi, r12
    lea rsi, [rip+.Lstr20]
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
    lea rsi, [rip+.Lstr21]
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
    lea rsi, [rip+.Lstr22]
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
    lea rsi, [rip+.Lstr23]
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
.Lsha_k:
    .long 1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221
    .long 3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580
    .long 3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986
    .long 2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895
    .long 666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037
    .long 2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344
    .long 430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779
    .long 1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298

.Lsha_h0:
    .long 1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225

.Lb64_alpha:
    .byte 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 45, 95

.Lb64_rev:
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 62, 255, 255
    .byte 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 255, 255, 255, 255, 255, 255
    .byte 255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
    .byte 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 255, 255, 255, 255, 63
    .byte 255, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40
    .byte 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255
    .byte 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255

.globl sha256_asm
sha256_asm:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x148
    mov [rsp+0x138], rsi
    mov [rsp+0x120], rdi
    mov rax, rdx
    shl rax, 3
    mov [rsp+0x128], rax
    mov BYTE PTR [rsi+rdx], 0x80
    inc rdx
    lea rcx, [rdx+71]
    and rcx, -64
    sub rcx, 8
.Lsha_zloop:
    cmp rdx, rcx
    jae .Lsha_zdone
    mov BYTE PTR [rsi+rdx], 0
    inc rdx
    jmp .Lsha_zloop
.Lsha_zdone:
    mov rax, [rsp+0x128]
    bswap rax
    mov [rsi+rcx], rax
    lea rax, [rcx+8]
    mov [rsp+0x130], rax
    lea rax, [rip+.Lsha_h0]
    xor rcx, rcx
.Lsha_init:
    mov edx, [rax+rcx*4]
    mov [rsp+0x100+rcx*4], edx
    inc rcx
    cmp rcx, 8
    jb .Lsha_init
    xor r14, r14
.Lsha_block:
    cmp r14, [rsp+0x130]
    jae .Lsha_fin
    xor rcx, rcx
    lea r15, [rsi+r14]
.Lsha_w16:
    mov eax, [r15+rcx*4]
    bswap eax
    mov [rsp+rcx*4], eax
    inc rcx
    cmp rcx, 16
    jb .Lsha_w16
.Lsha_w64:
    cmp rcx, 64
    jae .Lsha_rounds
    mov eax, [rsp+rcx*4-60]
    mov edx, eax
    mov r8d, eax
    ror eax, 7
    ror edx, 18
    shr r8d, 3
    xor eax, edx
    xor eax, r8d
    mov edx, [rsp+rcx*4-8]
    mov edi, edx
    mov r8d, edx
    ror edx, 17
    ror edi, 19
    shr r8d, 10
    xor edx, edi
    xor edx, r8d
    add eax, [rsp+rcx*4-64]
    add eax, edx
    add eax, [rsp+rcx*4-28]
    mov [rsp+rcx*4], eax
    inc rcx
    jmp .Lsha_w64
.Lsha_rounds:
    lea r15, [rip+.Lsha_k]
    mov r8d, [rsp+0x100]
    mov r9d, [rsp+0x104]
    mov r10d, [rsp+0x108]
    mov r11d, [rsp+0x10C]
    mov ebx, [rsp+0x110]
    mov ebp, [rsp+0x114]
    mov r12d, [rsp+0x118]
    mov r13d, [rsp+0x11C]
    xor rcx, rcx
.Lsha_rloop:
    mov eax, ebx
    mov edx, ebx
    ror eax, 6
    ror edx, 11
    xor eax, edx
    mov edx, ebx
    ror edx, 25
    xor eax, edx
    mov edi, ebx
    and edi, ebp
    mov edx, ebx
    not edx
    and edx, r12d
    xor edi, edx
    add edi, r13d
    add edi, eax
    mov eax, [r15+rcx*4]
    add edi, eax
    mov eax, [rsp+rcx*4]
    add edi, eax
    mov eax, r8d
    mov edx, r8d
    ror eax, 2
    ror edx, 13
    xor eax, edx
    mov edx, r8d
    ror edx, 22
    xor eax, edx
    mov edx, r8d
    and edx, r9d
    mov esi, r8d
    and esi, r10d
    xor edx, esi
    mov esi, r9d
    and esi, r10d
    xor edx, esi
    add edx, eax
    mov r13d, r12d
    mov r12d, ebp
    mov ebp, ebx
    lea ebx, [r11+rdi]
    mov r11d, r10d
    mov r10d, r9d
    mov r9d, r8d
    lea r8d, [rdi+rdx]
    inc rcx
    cmp rcx, 64
    jb .Lsha_rloop
    add [rsp+0x100], r8d
    add [rsp+0x104], r9d
    add [rsp+0x108], r10d
    add [rsp+0x10C], r11d
    add [rsp+0x110], ebx
    add [rsp+0x114], ebp
    add [rsp+0x118], r12d
    add [rsp+0x11C], r13d
    mov rsi, [rsp+0x138]
    add r14, 64
    jmp .Lsha_block
.Lsha_fin:
    mov rdi, [rsp+0x120]
    xor rcx, rcx
.Lsha_out:
    mov eax, [rsp+0x100+rcx*4]
    bswap eax
    mov [rdi+rcx*4], eax
    inc rcx
    cmp rcx, 8
    jb .Lsha_out
    add rsp, 0x148
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.globl hmac_asm
hmac_asm:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 0x1308
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    cmp r15, 4096
    ja hmac_asm_done_err
    xor rcx, rcx
hmac_asm_zk:
    cmp rcx, 64
    jae hmac_asm_kready
    mov BYTE PTR [rsp+rcx], 0
    inc rcx
    jmp hmac_asm_zk
hmac_asm_kready:
    cmp r13, 64
    jbe hmac_asm_kcopy
    lea rdi, [rsp+0x1220]
    mov rsi, r12
    mov rdx, r13
    call sha256_asm
    lea rsi, [rsp+0x1220]
    mov r12, rsi
    mov r13d, 32
hmac_asm_kcopy:
    xor rcx, rcx
hmac_asm_kcopyloop:
    cmp rcx, r13
    jae hmac_asm_kcopied
    mov al, [r12+rcx]
    mov [rsp+rcx], al
    inc rcx
    jmp hmac_asm_kcopyloop
hmac_asm_kcopied:
    xor rcx, rcx
hmac_asm_ipad:
    cmp rcx, 64
    jae hmac_asm_ipadded
    xor BYTE PTR [rsp+rcx], 0x36
    inc rcx
    jmp hmac_asm_ipad
hmac_asm_ipadded:
    xor rcx, rcx
hmac_asm_mcopy:
    cmp rcx, r15
    jae hmac_asm_mcopied
    mov al, [r14+rcx]
    mov [rsp+64+rcx], al
    inc rcx
    jmp hmac_asm_mcopy
hmac_asm_mcopied:
    lea rdi, [rsp+0x1220]
    mov rsi, rsp
    lea rdx, [r15+64]
    call sha256_asm
    xor rcx, rcx
hmac_asm_opad:
    cmp rcx, 64
    jae hmac_asm_opadded
    mov al, [rsp+rcx]
    xor al, 0x36
    xor al, 0x5c
    mov [rsp+0x1140+rcx], al
    inc rcx
    jmp hmac_asm_opad
hmac_asm_opadded:
    xor rcx, rcx
hmac_asm_odcopy:
    cmp rcx, 32
    jae hmac_asm_odcopied
    mov al, [rsp+0x1220+rcx]
    mov [rsp+0x1140+64+rcx], al
    inc rcx
    jmp hmac_asm_odcopy
hmac_asm_odcopied:
    mov rdi, rbx
    lea rsi, [rsp+0x1140]
    mov edx, 96
    call sha256_asm
    jmp hmac_asm_done
hmac_asm_done_err:
    xor eax, eax
    mov DWORD PTR [rbx], 0
hmac_asm_done:
    add rsp, 0x1308
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
.globl b64dec_asm
b64dec_asm:
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    mov r11, rcx
.Lb64d_strip:
    test r9, r9
    jz .Lb64d_stripped
    cmp BYTE PTR [r8+r9-1], 61
    jne .Lb64d_stripped
    dec r9
    jmp .Lb64d_strip
.Lb64d_stripped:
    mov rax, r9
    and eax, 3
    cmp eax, 1
    je .Lb64d_fail
    lea rax, [r9*2]
    add rax, r9
    shr rax, 2
    add rax, 3
    cmp rax, r11
    ja .Lb64d_fail
    xor rcx, rcx
    xor rdx, rdx
.Lb64d_loop4:
    mov rax, r9
    sub rax, rcx
    cmp rax, 4
    jb .Lb64d_tail
    lea r11, [rip+.Lb64_rev]
    xor edi, edi
    mov rsi, 4
.Lb64d_in4:
    movzx eax, BYTE PTR [r8+rcx]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    shl edi, 6
    or edi, eax
    inc rcx
    dec rsi
    jnz .Lb64d_in4
    mov eax, edi
    shr eax, 16
    mov [r10+rdx], al
    mov eax, edi
    shr eax, 8
    mov [r10+rdx+1], al
    mov [r10+rdx+2], dil
    add rdx, 3
    jmp .Lb64d_loop4
.Lb64d_tail:
    mov rax, r9
    sub rax, rcx
    cmp rax, 2
    jb .Lb64d_done
    je .Lb64d_two
    lea r11, [rip+.Lb64_rev]
    movzx eax, BYTE PTR [r8+rcx]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    shl eax, 18
    mov edi, eax
    movzx eax, BYTE PTR [r8+rcx+1]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    shl eax, 12
    or edi, eax
    movzx eax, BYTE PTR [r8+rcx+2]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    shl eax, 6
    or edi, eax
    mov eax, edi
    shr eax, 16
    mov [r10+rdx], al
    mov eax, edi
    shr eax, 8
    mov [r10+rdx+1], al
    add rdx, 2
    jmp .Lb64d_done
.Lb64d_two:
    lea r11, [rip+.Lb64_rev]
    movzx eax, BYTE PTR [r8+rcx]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    shl eax, 6
    mov edi, eax
    movzx eax, BYTE PTR [r8+rcx+1]
    movzx eax, BYTE PTR [r11+rax]
    cmp eax, 255
    je .Lb64d_fail
    or edi, eax
    mov eax, edi
    shr eax, 4
    mov [r10+rdx], al
    inc rdx
.Lb64d_done:
    mov rax, rdx
    ret
.Lb64d_fail:
    mov rax, -1
    ret
.globl b64enc_asm
b64enc_asm:
    mov r8, rdi
    mov r9, rsi
    mov r10, rdx
    xor rcx, rcx
    xor r11, r11
    lea rdx, [rip+.Lb64_alpha]
.Lb64e_loop:
    mov rax, r9
    sub rax, rcx
    cmp rax, 3
    jb .Lb64e_tail
    movzx edi, BYTE PTR [r8+rcx]
    shl edi, 16
    movzx eax, BYTE PTR [r8+rcx+1]
    shl eax, 8
    or edi, eax
    movzx eax, BYTE PTR [r8+rcx+2]
    or edi, eax
    mov eax, edi
    shr eax, 18
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11], al
    mov eax, edi
    shr eax, 12
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+1], al
    mov eax, edi
    shr eax, 6
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+2], al
    mov eax, edi
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+3], al
    add r11, 4
    add rcx, 3
    jmp .Lb64e_loop
.Lb64e_tail:
    mov rax, r9
    sub rax, rcx
    cmp rax, 2
    jb .Lb64e_one
    je .Lb64e_two
    movzx edi, BYTE PTR [r8+rcx]
    shl edi, 16
    movzx eax, BYTE PTR [r8+rcx+1]
    shl eax, 8
    or edi, eax
    movzx eax, BYTE PTR [r8+rcx+2]
    or edi, eax
    mov eax, edi
    shr eax, 18
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11], al
    mov eax, edi
    shr eax, 12
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+1], al
    mov eax, edi
    shr eax, 6
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+2], al
    mov eax, edi
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+3], al
    add r11, 4
    jmp .Lb64e_done
.Lb64e_two:
    movzx edi, BYTE PTR [r8+rcx]
    shl edi, 8
    movzx eax, BYTE PTR [r8+rcx+1]
    or edi, eax
    mov eax, edi
    shr eax, 10
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11], al
    mov eax, edi
    shr eax, 4
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11+1], al
    mov eax, edi
    and eax, 15
    shl eax, 2
    mov al, [rdx+rax]
    mov [r10+r11+2], al
    add r11, 3
    jmp .Lb64e_done
.Lb64e_one:
    cmp rax, 1
    jne .Lb64e_done
    movzx edi, BYTE PTR [r8+rcx]
    mov eax, edi
    shr eax, 2
    and eax, 63
    mov al, [rdx+rax]
    mov [r10+r11], al
    mov eax, edi
    and eax, 3
    shl eax, 4
    mov al, [rdx+rax]
    mov [r10+r11+1], al
    add r11, 2
.Lb64e_done:
    mov rax, r11
    ret
.globl utf8ok_asm
utf8ok_asm:
    xor rcx, rcx
.Lutf8_loop:
    cmp rcx, rsi
    jae .Lutf8_yes
    movzx eax, BYTE PTR [rdi+rcx]
    cmp eax, 0x80
    jb .Lutf8_next
    cmp eax, 0xC2
    jb .Lutf8_no
    cmp eax, 0xE0
    jb .Lutf8_need1
    cmp eax, 0xF0
    jb .Lutf8_lead3
    cmp eax, 0xF5
    jae .Lutf8_no
    movzx edx, BYTE PTR [rdi+rcx+1]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    cmp eax, 0xF0
    jne .Lutf8_l4mid
    cmp edx, 0x90
    jb .Lutf8_no
.Lutf8_l4mid:
    cmp eax, 0xF4
    jne .Lutf8_l4rest
    cmp edx, 0x8F
    ja .Lutf8_no
.Lutf8_l4rest:
    movzx edx, BYTE PTR [rdi+rcx+2]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    movzx edx, BYTE PTR [rdi+rcx+3]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    add rcx, 4
    jmp .Lutf8_loop
.Lutf8_lead3:
    movzx edx, BYTE PTR [rdi+rcx+1]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    cmp eax, 0xE0
    jne .Lutf8_l3mid
    cmp edx, 0xA0
    jb .Lutf8_no
.Lutf8_l3mid:
    cmp eax, 0xED
    jne .Lutf8_l3rest
    cmp edx, 0x9F
    ja .Lutf8_no
.Lutf8_l3rest:
    movzx edx, BYTE PTR [rdi+rcx+2]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    add rcx, 3
    jmp .Lutf8_loop
.Lutf8_need1:
    movzx edx, BYTE PTR [rdi+rcx+1]
    cmp edx, 0x80
    jb .Lutf8_no
    cmp edx, 0xBF
    ja .Lutf8_no
    add rcx, 2
    jmp .Lutf8_loop
.Lutf8_next:
    inc rcx
    jmp .Lutf8_loop
.Lutf8_yes:
    mov al, 1
    ret
.Lutf8_no:
    xor eax, eax
    ret
.globl jsonfind_asm
jsonfind_asm:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov rbp, rdx
    mov ebx, ecx
    mov r13, rdi
    lea r14, [rdi+rsi]
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 123
    jne .Ljf_notfound
    inc r13
.Ljf_pair:
.Ljf_ws1:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 32
    je .Ljf_ws1a
    cmp eax, 9
    je .Ljf_ws1a
    cmp eax, 10
    je .Ljf_ws1a
    cmp eax, 13
    jne .Ljf_ws1done
.Ljf_ws1a:
    inc r13
    jmp .Ljf_ws1
.Ljf_ws1done:
    cmp eax, 125
    je .Ljf_notfound
    cmp eax, 34
    jne .Ljf_notfound
    inc r13
    mov r15, r13
.Ljf_keyscan:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 92
    jne .Ljf_keychk
    add r13, 2
    jmp .Ljf_keyscan
.Ljf_keychk:
    cmp eax, 34
    je .Ljf_keyend
    inc r13
    jmp .Ljf_keyscan
.Ljf_keyend:
    mov rdi, r15
    mov rsi, r13
    sub rsi, r15
    mov rdx, rbp
    mov rcx, rbx
    push r13
    push r14
    sub rsp, 8
    call .Lstreq
    add rsp, 8
    pop r14
    pop r13
    mov r12d, eax
    inc r13
.Ljf_ws2:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 32
    je .Ljf_ws2a
    cmp eax, 9
    je .Ljf_ws2a
    cmp eax, 10
    je .Ljf_ws2a
    cmp eax, 13
    jne .Ljf_ws2done
.Ljf_ws2a:
    inc r13
    jmp .Ljf_ws2
.Ljf_ws2done:
    cmp eax, 58
    jne .Ljf_notfound
    inc r13
.Ljf_ws3:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 32
    je .Ljf_ws3a
    cmp eax, 9
    je .Ljf_ws3a
    cmp eax, 10
    je .Ljf_ws3a
    cmp eax, 13
    jne .Ljf_ws3done
.Ljf_ws3a:
    inc r13
    jmp .Ljf_ws3
.Ljf_ws3done:
    mov r15, r13
    cmp eax, 34
    je .Ljf_vstr
    cmp eax, 123
    je .Ljf_vnest
    cmp eax, 91
    je .Ljf_vnest
.Ljf_vlit:
    cmp r13, r14
    jae .Ljf_vend
    movzx eax, BYTE PTR [r13]
    cmp eax, 44
    je .Ljf_vend
    cmp eax, 125
    je .Ljf_vend
    cmp eax, 32
    je .Ljf_vend
    cmp eax, 9
    je .Ljf_vend
    cmp eax, 10
    je .Ljf_vend
    cmp eax, 13
    je .Ljf_vend
    inc r13
    jmp .Ljf_vlit
.Ljf_vstr:
    inc r13
.Ljf_vstrscan:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 92
    jne .Ljf_vstrchk
    add r13, 2
    jmp .Ljf_vstrscan
.Ljf_vstrchk:
    cmp eax, 34
    je .Ljf_vstrend
    inc r13
    jmp .Ljf_vstrscan
.Ljf_vstrend:
    inc r13
    jmp .Ljf_vend
.Ljf_vnest:
    mov rcx, 0
.Ljf_vnestloop:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 92
    jne .Ljf_vnestc
    add r13, 2
    jmp .Ljf_vnestloop
.Ljf_vnestc:
    cmp eax, 34
    jne .Ljf_vnestbr
    inc r13
.Ljf_vnstr:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 92
    jne .Ljf_vnstrc
    add r13, 2
    jmp .Ljf_vnstr
.Ljf_vnstrc:
    cmp eax, 34
    je .Ljf_vnstrend
    inc r13
    jmp .Ljf_vnstr
.Ljf_vnstrend:
    inc r13
    jmp .Ljf_vnestloop
.Ljf_vnestbr:
    cmp eax, 123
    jne .Ljf_vnestb2
    inc rcx
    inc r13
    jmp .Ljf_vnestloop
.Ljf_vnestb2:
    cmp eax, 91
    jne .Ljf_vnestb3
    inc rcx
    inc r13
    jmp .Ljf_vnestloop
.Ljf_vnestb3:
    cmp eax, 125
    jne .Ljf_vnestb4
    dec rcx
    inc r13
    test rcx, rcx
    jnz .Ljf_vnestloop
    jmp .Ljf_vend
.Ljf_vnestb4:
    cmp eax, 93
    jne .Ljf_vnestb5
    dec rcx
    inc r13
    test rcx, rcx
    jnz .Ljf_vnestloop
    jmp .Ljf_vend
.Ljf_vnestb5:
    inc r13
    jmp .Ljf_vnestloop
.Ljf_vend:
    test r12d, r12d
    jnz .Ljf_got
.Ljf_ws4:
    cmp r13, r14
    jae .Ljf_notfound
    movzx eax, BYTE PTR [r13]
    cmp eax, 32
    je .Ljf_ws4a
    cmp eax, 9
    je .Ljf_ws4a
    cmp eax, 10
    je .Ljf_ws4a
    cmp eax, 13
    jne .Ljf_ws4done
.Ljf_ws4a:
    inc r13
    jmp .Ljf_ws4
.Ljf_ws4done:
    cmp eax, 44
    jne .Ljf_notfound
    inc r13
    jmp .Ljf_pair
.Ljf_got:
    mov rax, r15
    mov r8, r13
    sub r8, r15
    jmp .Ljf_ret
.Ljf_notfound:
    xor eax, eax
    xor r8d, r8d
.Ljf_ret:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret
.globl parseexp_asm
parseexp_asm:
    xor eax, eax
    xor edx, edx
    xor rcx, rcx
    xor r8d, r8d
    cmp rcx, rsi
    jae .Lpe_bad
    movzx r9d, BYTE PTR [rdi]
    cmp r9d, 45
    jne .Lpe_digits
    mov edx, 1
    inc rcx
.Lpe_digits:
    cmp rcx, rsi
    jae .Lpe_end
    movzx r9d, BYTE PTR [rdi+rcx]
    sub r9d, 48
    cmp r9d, 9
    ja .Lpe_end
    mov r10, 0x7FFFFFFFFFFFFFFF
    sub r10, r9
    mov r11, rax
    cmp r11, r10
    ja .Lpe_saturate
    imul rax, rax, 10
    add rax, r9
    inc rcx
    inc r8
    jmp .Lpe_digits
.Lpe_saturate:
    mov rax, 0x7FFFFFFFFFFFFFFF
    inc rcx
    inc r8
.Lpe_sskip:
    cmp rcx, rsi
    jae .Lpe_end
    movzx r9d, BYTE PTR [rdi+rcx]
    sub r9d, 48
    cmp r9d, 9
    ja .Lpe_end
    inc rcx
    jmp .Lpe_sskip
.Lpe_end:
    test r8d, r8d
    jz .Lpe_bad
    test edx, edx
    jz .Lpe_ok
    neg rax
.Lpe_ok:
    mov edx, 1
    ret
.Lpe_bad:
    xor eax, eax
    xor edx, edx
    ret
.Lauth_check:
    push rbx
    push r12
    sub rsp, 0x908
    movsx rax, DWORD PTR [rbx+APPREQ_AUTH_LEN]
    cmp rax, 0
    jl .Lac_missing
    cmp rax, 7
    jl .Lac_missing
    mov rdi, [rbx+APPREQ_AUTH]
    movsx rsi, DWORD PTR [rbx+APPREQ_AUTH_LEN]
    lea rdx, [rip+.Lstr24]
    mov ecx, 7
    call .Lstreqpfx
    test al, al
    jz .Lac_missing
    mov rax, [rbx+APPREQ_AUTH]
    add rax, 7
    mov [rsp+0x8A0], rax
    movsx rax, DWORD PTR [rbx+APPREQ_AUTH_LEN]
    sub rax, 7
    mov [rsp+0x8A8], rax
    cmp rax, 2048
    ja .Lac_invalid
    xor rcx, rcx
    mov rdx, [rsp+0x8A0]
    mov rsi, [rsp+0x8A8]
.Lac_d1:
    cmp rcx, rsi
    jae .Lac_invalid
    cmp BYTE PTR [rdx+rcx], 46
    je .Lac_d1ok
    inc rcx
    jmp .Lac_d1
.Lac_d1ok:
    test rcx, rcx
    jz .Lac_invalid
    mov r8, rcx
    inc rcx
    mov r9, rcx
.Lac_d2:
    cmp rcx, rsi
    jae .Lac_invalid
    cmp BYTE PTR [rdx+rcx], 46
    je .Lac_d2ok
    inc rcx
    jmp .Lac_d2
.Lac_d2ok:
    mov r10, rcx
    sub r10, r9
    test r10, r10
    jz .Lac_invalid
    inc rcx
    mov rax, rsi
    sub rax, rcx
    test rax, rax
    jz .Lac_invalid
    mov r11, rcx
.Lac_d3:
    cmp r11, rsi
    jae .Lac_d3ok
    cmp BYTE PTR [rdx+r11], 46
    je .Lac_invalid
    inc r11
    jmp .Lac_d3
.Lac_d3ok:
    mov [rsp+0x8B8], r10
    mov rax, [rsp+0x8A0]
    add rax, r9
    mov [rsp+0x8B0], rax
    mov rax, [rsp+0x8A0]
    add rax, rcx
    mov [rsp+0x8C0], rax
    mov rax, [rsp+0x8A8]
    sub rax, rcx
    mov [rsp+0x8C8], rax
    mov rax, r8
    add rax, r10
    add rax, 1
    mov [rsp+0x8D0], rax
    mov rdi, [rsp+0x8A0]
    mov rsi, r8
    lea rdx, [rsp]
    mov ecx, 512
    call b64dec_asm
    cmp rax, 0
    jl .Lac_invalid
    mov rsi, rax
    lea rdi, [rsp]
    push rsi
    push rdi
    sub rsp, 8
    call utf8ok_asm
    add rsp, 8
    pop rdi
    pop rsi
    test al, al
    jz .Lac_invalid
    lea rdx, [rip+.Lstr25]
    mov ecx, 3
    call jsonfind_asm
    test rax, rax
    jz .Lac_invalid
    mov rdi, rax
    mov rsi, r8
    lea rdx, [rip+.Lstr26]
    mov ecx, 7
    call .Lstreq
    test al, al
    jz .Lac_invalid
    mov rdi, [rsp+0x8B0]
    mov rsi, [rsp+0x8B8]
    lea rdx, [rsp+0x200]
    mov ecx, 1536
    call b64dec_asm
    cmp rax, 0
    jl .Lac_invalid
    mov rsi, rax
    lea rdi, [rsp+0x200]
    push rsi
    push rdi
    sub rsp, 8
    call utf8ok_asm
    add rsp, 8
    pop rdi
    pop rsi
    test al, al
    jz .Lac_invalid
    mov [rsp+0x8E0], rsi
    mov rdi, [rsp+0x8C0]
    mov rsi, [rsp+0x8C8]
    lea rdx, [rsp+0x800]
    mov ecx, 64
    call b64dec_asm
    cmp rax, 0
    jl .Lac_invalid
    lea rdi, [rsp+0x840]
    mov rsi, [rip+g_secret_ptr]
    mov rdx, [rip+g_secret_len]
    mov rcx, [rsp+0x8A0]
    mov r8, [rsp+0x8D0]
    call hmac_asm
    lea rdi, [rsp+0x840]
    mov esi, 32
    lea rdx, [rsp+0x860]
    call b64enc_asm
    mov r8, rax
    cmp r8, [rsp+0x8C8]
    jne .Lac_invalid
    lea rdi, [rsp+0x860]
    mov rsi, [rsp+0x8C0]
    xor rcx, rcx
.Lac_scmp:
    cmp rcx, r8
    jae .Lac_sigok
    mov al, [rdi+rcx]
    cmp al, [rsi+rcx]
    jne .Lac_invalid
    inc rcx
    jmp .Lac_scmp
.Lac_sigok:
    lea rdi, [rsp+0x200]
    mov rsi, [rsp+0x8E0]
    lea rdx, [rip+.Lstr27]
    mov ecx, 3
    call jsonfind_asm
    test rax, rax
    jz .Lac_invalid
    mov rdi, rax
    mov rsi, r8
    call parseexp_asm
    test edx, edx
    jz .Lac_invalid
    mov r9, rax
    push r9
    sub rsp, 8
    call x_now
    add rsp, 8
    pop r9
    cmp r9, rax
    jle .Lac_invalid
    lea rdi, [rsp+0x200]
    mov rsi, [rsp+0x8E0]
    lea rdx, [rip+.Lstr28]
    mov ecx, 3
    call jsonfind_asm
    test rax, rax
    jz .Lac_badpayload
    cmp r8, 2
    jb .Lac_badpayload
    cmp BYTE PTR [rax], 34
    jne .Lac_badpayload
    cmp BYTE PTR [rax+r8-1], 34
    jne .Lac_badpayload
    lea rdi, [rax+1]
    mov rsi, r8
    sub rsi, 2
    push rsi
    push rdi
    sub rsp, 8
    call parseid_asm
    add rsp, 8
    pop rdi
    pop rsi
    test edx, edx
    jz .Lac_badpayload
    mov [rip+g_uid], rax
    lea rdi, [rsp+0x200]
    mov rsi, [rsp+0x8E0]
    lea rdx, [rip+.Lstr29]
    mov ecx, 8
    call jsonfind_asm
    test rax, rax
    jz .Lac_badpayload
    cmp r8, 2
    jb .Lac_badpayload
    cmp BYTE PTR [rax], 34
    jne .Lac_badpayload
    cmp BYTE PTR [rax+r8-1], 34
    jne .Lac_badpayload
    inc rax
    mov [rip+g_uname_ptr], rax
    mov rax, r8
    sub rax, 2
    mov [rip+g_uname_len], rax
    xor eax, eax
    jmp .Lac_ret
.Lac_missing:
    mov eax, 1
    jmp .Lac_ret
.Lac_invalid:
    mov eax, 2
    jmp .Lac_ret
.Lac_badpayload:
    mov eax, 3
.Lac_ret:
    add rsp, 0x908
    pop r12
    pop rbx
    ret
.globl jsonfind_c_asm
jsonfind_c_asm:
    push r8
    call jsonfind_asm
    pop rcx
    mov [rcx], r8
    ret
.globl parseid_c_asm
parseid_c_asm:
    push rdx
    call parseid_asm
    pop rcx
    mov [rcx], edx
    ret
.globl parseexp_c_asm
parseexp_c_asm:
    push rdx
    call parseexp_asm
    pop rcx
    mov [rcx], edx
    ret
.section .rodata
.Lstr0:
    .byte 47, 104, 101, 97, 108, 116, 104
.Lstr1:
    .byte 47, 102, 101, 101, 100
.Lstr2:
    .byte 47, 112, 111, 115, 116, 115, 47
.Lstr3:
    .byte 47, 112, 111, 115, 116, 115
.Lstr4:
    .byte 47, 108, 105, 107, 101
.Lstr5:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 110, 111, 116, 32, 102, 111, 117, 110, 100, 34, 125
.Lstr6:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 105, 110, 118, 97, 108, 105, 100, 32, 112, 111, 115, 116, 32, 105, 100, 34, 125
.Lstr7:
    .byte 83, 69, 76, 69, 67, 84, 32, 49
.Lstr8:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 111, 107, 34, 44, 34, 100, 98, 34, 58, 34, 111, 107, 34, 44, 34, 117, 112, 116, 105, 109, 101, 95, 115, 34, 58
.Lstr9:
    .byte 123, 34, 115, 116, 97, 116, 117, 115, 34, 58, 34, 100, 101, 103, 114, 97, 100, 101, 100, 34, 44, 34, 100, 98, 34, 58, 34, 117, 110, 114, 101, 97, 99, 104, 97, 98, 108, 101, 34, 44, 34, 101, 114, 114, 111, 114, 34, 58
.Lstr10:
    .byte 83, 69, 76, 69, 67, 84, 32, 112, 46, 105, 100, 44, 32, 112, 46, 98, 111, 100, 121, 44, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 44, 32, 117, 46, 117, 115, 101, 114, 110, 97, 109, 101, 44, 32, 40, 83, 69, 76, 69, 67, 84, 32, 99, 111, 117, 110, 116, 40, 42, 41, 32, 70, 82, 79, 77, 32, 108, 105, 107, 101, 115, 32, 108, 32, 87, 72, 69, 82, 69, 32, 108, 46, 112, 111, 115, 116, 95, 105, 100, 32, 61, 32, 112, 46, 105, 100, 41, 32, 65, 83, 32, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 32, 70, 82, 79, 77, 32, 112, 111, 115, 116, 115, 32, 112, 32, 74, 79, 73, 78, 32, 117, 115, 101, 114, 115, 32, 117, 32, 79, 78, 32, 117, 46, 105, 100, 32, 61, 32, 112, 46, 117, 115, 101, 114, 95, 105, 100, 32, 79, 82, 68, 69, 82, 32, 66, 89, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 32, 68, 69, 83, 67, 44, 32, 112, 46, 105, 100, 32, 68, 69, 83, 67, 32, 76, 73, 77, 73, 84, 32, 50, 48
.Lstr11:
    .byte 123, 34, 112, 111, 115, 116, 115, 34, 58, 91
.Lstr12:
    .byte 93, 125
.Lstr13:
    .byte 83, 69, 76, 69, 67, 84, 32, 112, 46, 105, 100, 44, 32, 112, 46, 98, 111, 100, 121, 44, 32, 112, 46, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 44, 32, 117, 46, 117, 115, 101, 114, 110, 97, 109, 101, 44, 32, 40, 83, 69, 76, 69, 67, 84, 32, 99, 111, 117, 110, 116, 40, 42, 41, 32, 70, 82, 79, 77, 32, 108, 105, 107, 101, 115, 32, 108, 32, 87, 72, 69, 82, 69, 32, 108, 46, 112, 111, 115, 116, 95, 105, 100, 32, 61, 32, 112, 46, 105, 100, 41, 32, 65, 83, 32, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 32, 70, 82, 79, 77, 32, 112, 111, 115, 116, 115, 32, 112, 32, 74, 79, 73, 78, 32, 117, 115, 101, 114, 115, 32, 117, 32, 79, 78, 32, 117, 46, 105, 100, 32, 61, 32, 112, 46, 117, 115, 101, 114, 95, 105, 100, 32, 87, 72, 69, 82, 69, 32, 112, 46, 105, 100, 32, 61, 32, 63
.Lstr14:
    .byte 123, 34, 112, 111, 115, 116, 34, 58
.Lstr15:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 112, 111, 115, 116, 32, 110, 111, 116, 32, 102, 111, 117, 110, 100, 34, 125
.Lstr16:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 109, 105, 115, 115, 105, 110, 103, 32, 98, 101, 97, 114, 101, 114, 32, 116, 111, 107, 101, 110, 34, 125
.Lstr17:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 105, 110, 118, 97, 108, 105, 100, 32, 111, 114, 32, 101, 120, 112, 105, 114, 101, 100, 32, 116, 111, 107, 101, 110, 34, 125
.Lstr18:
    .byte 123, 34, 101, 114, 114, 111, 114, 34, 58, 34, 105, 110, 118, 97, 108, 105, 100, 32, 116, 111, 107, 101, 110, 32, 112, 97, 121, 108, 111, 97, 100, 34, 125
.Lstr19:
    .byte 123, 34, 105, 100, 34, 58
.Lstr20:
    .byte 44, 34, 98, 111, 100, 121, 34, 58, 34
.Lstr21:
    .byte 34, 44, 34, 99, 114, 101, 97, 116, 101, 100, 95, 97, 116, 34, 58, 34
.Lstr22:
    .byte 34, 44, 34, 97, 117, 116, 104, 111, 114, 34, 58, 34
.Lstr23:
    .byte 34, 44, 34, 108, 105, 107, 101, 95, 99, 111, 117, 110, 116, 34, 58
.Lstr24:
    .byte 66, 101, 97, 114, 101, 114, 32
.Lstr25:
    .byte 97, 108, 103
.Lstr26:
    .byte 34, 72, 83, 50, 53, 54, 34
.Lstr27:
    .byte 101, 120, 112
.Lstr28:
    .byte 115, 117, 98
.Lstr29:
    .byte 117, 115, 101, 114, 110, 97, 109, 101
.section .bss
.align 8
g_secret_ptr: .quad 0
g_secret_len: .quad 0
g_uid: .quad 0
g_uname_ptr: .quad 0
g_uname_len: .quad 0

.section .note.GNU-stack,"",@progbits

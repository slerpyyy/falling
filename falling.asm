org 100h

start:
    push    0A000h - 70     ; modified to center to 160,100
    aas                     ; make aspect ratio float of ~1.24
    mov     cx,bx

    pop     es              ; ES -> ScreenPointer
    mov     al,13h
    int     10h             ; mode 13h

palette:
    mov     dx,0x3c8
    out     dx,al
    inc     dx
    out     dx,al
    out     dx,al
    out     dx,al
    inc     ax
    jnz     palette

bigloop:
    mov     ax,0xCCCD   ; Rrrola's trick
    mul     di          ; to approximate centered coords from DI in range [0..65535]
    sub     dh,[si]     ; align vertically (subtract 104)
    pusha

    ; skip sound code
    and     al, al
    jnz     grapfics

    ; set direct mode on sound blaster
    mov     dx, 22ch    ; 22ch = 220h (sound driver) + ch (config port)
    mov     al, 10h     ; 10h = 'Direct Mode'
    out     dx, al

    ;------------------------------------------------------------
    ; Audio Code
    ;------------------------------------------------------------

    ; In this section, 2 global variables are stored
    ; in a safe section of the stack red zone:
    %define _Sample si-08   ; audio sample counter
    %define _Last   si-12   ; last calculated audio sample

    ; set accumulator a = 0
    fldz                    ; a

    ; get time from sample counter
    fild    dword [_Sample] ; c   a
    fidiv   word [_Rate]    ; t   a

    push    cx
    mov     cx, 4
voiceloop:

    ; offset voice
    fld     dword [_0_5]    ; 1/2 t   a
    fmul    st0, st0
    fimul   word [_Period]  ; P/4 t   a
    faddp                   ; t   a

    ; x = mod(t, P)
    fild    word [_Period]  ; P   t   a
    fld     st1             ; t   P   t   a
    fprem                   ; x   P   t   a

    ; xp = x / P;
    fxch                    ; P   x   t   a
    fdivr   st0, st1        ; xp  x   t   a

    ; y = B * x * (2 - xp);
    fld1
    fadd    st0, st0        ; 2   xp  x   t   a
    fsub    st0, st1
    fmul    st0, st2
    fimul   word [_Base]    ; y   xp  x   t   a

    ; square wave call
    call    square          ; y   1   xp  x   t   a
    fxch                    ; 1   y   xp  x   t   a

    ; d = 2 * xp - 1
    fld     st2             ; xp  1   y   xp  x   t   a
    fadd    st0, st0        ; 2xp 1   y   xp  x   t   a
    fsub    st0, st1        ; d   1   y   xp  x   t   a

    ; d = 1 - abs(d)
    fabs
    fsubp                   ; d   y   xp  x   t   a
;   fmul    st0, st0

    ; a += d * y
    fmulp                   ; dy  xp  x   t   a
    faddp   st4, st0        ; xp  x   t   a'

    ; stack clean up
    fcompp                  ; just here for that double pop

    loop    voiceloop
    pop     cx

    ; final clean up
    fstp    st0             ; a

    ; range correction [-1, 1] --> [0, 255]
    fimul   word [_Amp]

    ; simple low-pass filter
    fiadd   word [_Last]
    fmul    dword [_0_5]
    fistp   word [_Last]

    ; send byte audio sample
    mov     ax, [_Last]
    out     dx, al

    ; increment sample index
    inc     dword [_Sample]

    ;------------------------------------------------------------
    ; Graphics Code
    ;------------------------------------------------------------

grapfics:
    ; c = 0.5 / abs(x)
    fild    word [bx-9]     ; load x
    fidiv   word [_Res]     ; normalize to [-1..1]
    fabs
    fld     dword [_0_5]
    fdiv    st0, st1        ; c   x

    ; c = max(c, 1)
    fld1                    ; 1   c   x
    fcom
    fstsw   ax              ; moves FPU status to ax
    sahf                    ; moves ah to eflags
    jb      noswap          ; jump if "below" (unsigned comparison)
    fxch
noswap:
    fstp    st0

    ; c *= y
    fild    word [bx-8]     ; load y
    fidiv   word [_Res]     ; normalize to [-1..1]
    fmulp

    ; c = y * (1 + abs(x))
;   fild    word [bx-9]     ; load x
;   fdiv    dword [_Res]    ; normalize to [-1..1]
;   fabs
;   fld1
;   faddp
;   fild    word [bx-8]     ; load y
;   fdiv    dword [_Res]    ; normalize to [-1..1]
;   fmulp

    ; c += time
    fild    word [_Speed]
    mov     [si-4], cx
    fild    dword [si-4]
    fdiv    st0, st1
    faddp
    faddp
;   mov     [si-4], cx      ; places frame couter in stack red zone
;   fild    dword [si-4]
;   fidiv   word [_Speed]
;   fiadd   word [_Speed]   ; offset to hide truncating weirdness near zero
;   faddp

    ; another square wave call
    call    square
    fmulp

    ; distance fog / fade
    fmulp                   ; mul brightness with abs(x)
    f2xm1                   ; OPTIONAL (2 bytes)

    ;output pixel
    fimul   word [_Br]      ; output must be in range 0..63 (grayscale)
    fistp   word [bx-4]     ; store to ax slot (will be in ax after popa)
    popa
    stosb                   ; AL -> pixel, increment DI

    ; timer increment and esc check after each frame
    and     di, di
    jnz     bigloop
    inc     cx

    ;------------------------------------------------------------
    ; NOT OPTIONAL: check for ESC
    ;------------------------------------------------------------
    in      al, 60h
    dec     al
    jnz     bigloop

    ;------------------------------------------------------------
    ; OPTIONAL: switch back to text mode
    ;------------------------------------------------------------
    mov     ax, 03      ; AH must be 00h
    int     10h         ; mode 03h

    ;------------------------------------------------------------
    ; exit
    ;------------------------------------------------------------
;   ret                 ; it's fine, the function has a return

square:         ; x   ...
    fld1
    fxch        ; x   1   ...
    fprem
    frndint
    ret         ; y   1   ...

_Data:
  _Res:     dw  7fffh       ; const for normalizing screen coords
  _Rate:    db  80h ;3e80h  ; number of samples per second
  _Amp:    ;dw  002ah       ; 4*amp < 256 to prevent overflowing
  _Br:     ;dw  003fh       ; grayscale brightness multiplier
  _Speed:  ;dw  0030h       ; speed divider for scroll effect
  _0_5:    ;dd  0.5         ; 0.5 const (hugging other constant)
  _Period:  dw  003eh ;3ch  ; time for one voice to reset
            dw  3f00h
  _Base:    dw  00dch       ; lower voice freq (2*base --> base)


    ;------------------------------------------------------------
    ; VERY OPTIONAL: Type message
    ;------------------------------------------------------------

;   db "Rev"                ;  3 bytes
;   db "Rev19"              ;  5 bytes
;   db "Rev2019"            ;  7 bytes
    db "Revision"           ;  8 bytes
;   db "Revision19"         ; 10 bytes
;   db "Revision2019"       ; 12 bytes

    db 03h  ; (heart symbol)  +1 byte
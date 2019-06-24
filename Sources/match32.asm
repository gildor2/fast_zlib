;------------------------------------------------------------------------------
; Fast version of the longest_match function for zlib
; Copyright (C) 2004-2019 Konstantin Nosov
; For details and updates please visit
; http://github.com/gildor2/fast_zlib
; Licensed under the BSD license. See LICENSE.txt file in the project root for
; full license information.
;------------------------------------------------------------------------------

; How to compile:
;  - Use the following command line: nasm match.asm
;  - To compile for Delphi/WatcomC/BorlandC add "-DOMF_FORMAT -fobj" command line options.
;  - For Windows / VisualC add "-f win32"
;  - If your C compiler requires leading underscore, add "--prefix _" option. Please note
;    that this implementation already defines 2 symbols for longest_match: with and without
;    leading underscore.
; For zlib of version 1.2.2 and older, you should define OLD_ZLIB macro. 1.2.2.1 and newer
; doesn't require this definition.

; For more details please refer to README.md at the project's root directory.

; Some optimization notes:
;  - "movzx reg32,word [mem]" is faster than "mov reg16,word [mem]"
;  - "movzx eax,ax" is faster than "and eax,0xFFFF"
;  - unrolled "rep cmpsd" faster

;?? TODO: can use __OUTPUT_FORMAT__ macro to detect OMF (obj) and COFF (win32)

		bits	32
		global	longest_match, match_init

; Configuration (do not change unless for testing)

;%define ALWAYS_ZERO_OFFSET			; DEBUG: work just like original algorithm, with zero offset; the performance will be nearly equal
						; to original zlib with asm optimization

; Debugging options

;%define BREAKPOINT_AT	0x7F9D


;------------------------------------------------------------------------------
;		Zlib constants
;------------------------------------------------------------------------------

MIN_MATCH	equ	3			; should not be changed !
MAX_MATCH	equ	258
MIN_LOOKAHEAD	equ	(MAX_MATCH+MIN_MATCH+1)
MIN_CHAIN_LEN	equ	64			; should be greater than max_chain_length in any deflate_fast() level (1-4)


;------------------------------------------------------------------------------
;		Zlib structures
;------------------------------------------------------------------------------

; this macro will allow us to reduce size of struc declaration
%macro struc_vars 1-*
	%rep %0
%1		resd 1
		%rotate 1
	%endrep
%endmacro

; deflate_state (DST) structure layout
		struc DST
		struc_vars .strm, .status
		struc_vars .pending_buf, .pending_buf_size, .pending_out, .pending, .wrap
%ifdef OLD_ZLIB
		; zlib version <= 1.2.2
.data_type	resb 1
%else
		; changes in zlib 1.2.2 are compatible (removed data_type byte field, but method field
		;   is unused in current file)
		; changes in zLib 1.2.2.1 are incompatible
		struc_vars .gzhead, .gzindex
%endif
.method		resb 1
		alignb	4			; alignment for the next field

		struc_vars .last_flush

		struc_vars .w_size, .w_bits, .w_mask, .window, .window_size, .prev
		struc_vars .head, .ins_h, .hash_size, .hash_bits, .hash_mask, .hash_shift

		struc_vars .block_start

		struc_vars .match_length, .prev_match, .match_available, .strstart, .match_start
		struc_vars .lookahead
		struc_vars .prev_length, .max_chain_length
		struc_vars .max_lazy_match, .level, .strategy
		struc_vars .good_match, .nice_match

		; .......... (more) ...........

		endstruc


;------------------------------------------------------------------------------
;		Macros for defining stack variables
;------------------------------------------------------------------------------
; Usage notes:
; 1. do not use vars inside PUSH/POP blocks
; 2. place end_vars macro before returning from function
; 3. between begin_vars and end_vars may be placed only res_var macros
; 4. var allocation:
;    a) res_var <name> - reserve space (actually will be allocated with end_vars macro)
;    b) add_var <name>,<value> - reserve and initialize variable (using PUSH operation)
; 5. if you'll try to define one variable twice, nasm will display LONG list of unrelated
;    errors (cannot check definition with "%ifdef %1" - )

%macro begin_vars 0
	%push stack
	%assign %$stacksize 0
%endmacro

%macro end_vars 0
	%ifidn %$stacksize,4
		push	eax			; faster, smaller
	%elifnidn %$stacksize,0
		sub	esp,%$stacksize		; generic version
	%endif
%endmacro

%macro res_var 1
;	%ifdef %1  -- not works !
;		%error variable redifinition: %1
;	%endif
	%assign %$stacksize %$stacksize+4
	%assign var_%1 %$stacksize
	%define %1 esp+%$stacksize-var_%1
%endmacro

%macro add_var 2
		res_var %1
		push	dword %2
%endmacro

%macro drop_vars 0
	%ifnidn %$stacksize,0
		add	esp,%$stacksize
	%endif
%endmacro

%macro _push 1
		push	%1
	%assign %$stacksize %$stacksize+4
%endmacro

%macro _pop 1
		pop	%1
	%assign %$stacksize %$stacksize-4
%endmacro


;------------------------------------------------------------------------------
; helper macros

%macro push 1-*
	%rep %0
		push	%1
		%rotate 1
	%endrep
%endmacro

%macro pop 1-*
	%rep %0
		pop	%1
		%rotate 1
	%endrep
%endmacro

%imacro xalign 1.nolist
	%if ((%1-1) & %1) || (%1 > 16)
		%error Error! XALIGN %1 - incorrect alignment
	%endif
	%assign %%count ($$-$) & ((%1)-1)
	%if %%count == 1
		nop
	%elif %%count == 2
		mov	eax,eax
	%elif %%count == 3
		lea	esp,[esp]
	%elif %%count >= 4
		jmp short %%skip
		times %%count-2 nop
		%%skip:
	%endif
	%if ($$-$) & ((%1)-1)
		%error Error! XALIGN generated incorrect code
	%endif
%endmacro


;------------------------------------------------------------------------------
;		Code segment
;------------------------------------------------------------------------------

%ifdef OMF_FORMAT
; Section definition for Watcom C
SECTION _TEXT public align=16 class=CODE use32
%else
SECTION .text
%endif

;------------------------------------------------------------------------------
; uInt longest_match(deflate_state *s, IPos cur_match)

global longest_match, _longest_match

longest_match:
_longest_match:
		push	ebx,ecx,edx,esi,edi,ebp

		mov	esi,[esp+28]		; DEFLATE_STATE *s
		mov	ebp,[esp+32]		; cur_match

		begin_vars
		res_var chain_mask
		end_vars

%ifdef BREAKPOINT_AT
		mov	eax,[esi+DST.strstart]
		cmp	eax,BREAKPOINT_AT
		jnz	.cont
		nop				; set breakpoint here
.cont:
%endif
		add_var best_len,[esi+DST.prev_length]
		add_var nice_match,[esi+DST.nice_match]
		add_var str_start,[esi+DST.strstart]
		add_var hash_shift,[esi+DST.hash_shift]
		add_var hash_heads,[esi+DST.head]
		add_var hash_mask,[esi+DST.hash_mask]

		mov	eax,[esi+DST.window]	; match_base = s->window
		add_var match_base,eax
		add	eax,[str_start]		; scan = s->window + s->strstart
		add_var scan,eax
		mov	ebx,[eax]		; scan_start = *scan
		add_var scan_start,ebx
		add	eax,[best_len]		; scan_end = *scan[best_len-3]
		sub	eax,3
		mov	ebx,[eax]
		add_var scan_end,ebx
		mov	eax,[match_base]	; match_base2 = match_base+best_len-3
		add	eax,[best_len]
		sub	eax,3
		add_var match_base2,eax

		; limit = s->strstart - (s->w_size - MIN_LOOKAHEAD)
		mov	eax,[esi+DST.strstart]
		add	eax,MIN_LOOKAHEAD
		sub	eax,[esi+DST.w_size]
		jae	.limit_ok
		xor	eax,eax
.limit_ok:
		add_var limit_base,eax
		add_var limit,eax
		; offset = 0
		add_var offset,0
		add_var old_offset,0
		; prev
		mov	edi,[esi+DST.prev]
		add_var prev,edi
		; chain_length = s->max_chain_length
		mov	ebx,[esi+DST.max_chain_length]
		cmp	ebx,MIN_CHAIN_LEN
		jae	.new_mode
		; avoid offset matches when max_chain_length is smaller than MIN_CHAIN_LEN (cur_match+len will be always > str_start ...)
		mov	dword [str_start],0
.new_mode:
		dec	ebx			; originally, break condition is "--chain_len == 0"; here we'll stop on "--chain_length<0" ...
		; if (best_len >= s->good_match) chain_length >>= 2
		mov	eax,[best_len]
		cmp	eax,[esi+DST.good_match]
		jb	.chain_len_ok
		shr	ebx,2
.chain_len_ok:
		shl	ebx,16
		; wmask = s->w_mask
		mov	bx,word [esi+DST.w_mask]
		; HERE: EBX contains [chain_length|wmask] (idea from match686.asm)

		; if (nice_match > s->lookahead) nice_match = s->lookahead
		mov	eax,[esi+DST.lookahead]
		cmp	eax,[nice_match]
		jae	.nice_ok
		mov	[nice_match],eax
.nice_ok:
		add_var	deflate_state,esi	; rare used

		; alignment of scan: 0->+0, 1->+3, 2->+2, 3->+1
		mov	eax,[scan]
		add	eax,3
		and	eax,~3
		add_var scan_aligned,eax	;?? not used
		sub	eax,[scan]
		add_var align_shift,eax
		; scan_max = scan + MAX_MATCH
		mov	eax,[scan]
		add	eax,MAX_MATCH
		add_var scan_max,eax

		mov	esi,ebx

		;---------------------
		; global vars:
		;   EBP - cur_match
		;   EDI - prev

		; ESI = wmask | chain_length << 16

;------------------------------------------------
%ifndef ALWAYS_ZERO_OFFSET
		cmp	dword [best_len],MIN_MATCH
		jb	.main_loop
		mov	[chain_mask],esi	; save value
		mov	esi,[scan]
		mov	edi,3			; index of last checked byte + start checking from pos+1 (pos+0->strstart->cur_match)
		mov	ecx,[hash_shift]
		mov	edx,[hash_heads]

		; 1st byte
		movzx	ebx,byte [esi+1]
		; 2nd byte
		shl	ebx,cl
		xor	bl,[esi+2]

		; misc vars: EAX
		; loop vars: EBX=hash, ECX=hash_shift, EDX=hash_heads, ESI->scan, EDI=index+2, EBP=cur_match

		xalign	4
		; 3rd byte
.init_match_loop:
		shl	ebx,cl
		xor	bl,[esi+edi]
		and	ebx,[hash_mask]

		movzx	eax,word [edx+ebx*2]

		cmp	eax,ebp
		jae	.cont_init_match
;		cmp	eax,[limit]
;		jbe	.break_match
		mov	ebp,eax			; cur_match = match
		lea	eax,[edi-2]
		mov	[offset],eax		; offset = index

.cont_init_match:
		inc	edi
		cmp	edi,[best_len]
		jbe	.init_match_loop

		; load ESI,EDI
		mov	esi,[chain_mask]
		mov	edi,[prev]
		; match_base[2] -= offset;
		mov	eax,[offset]
		add	[limit],eax		; limit = limit_base + offset
		cmp	ebp,[limit]
		jbe	.break_match
		mov	[old_offset],eax
		neg	eax
		add	[match_base],eax
		add	[match_base2],eax
%endif ; ALWAYS_ZERO_OFFSET
;------------------------------------------------

		xalign	4
.main_loop:
		cmp	dword [best_len],3
		mov	ecx,[match_base]
		jbe	.short_test2

;%define MATCH_DWORD1				; faster, when OFF

		mov	eax,[match_base2]
%ifndef MATCH_DWORD1
		movzx	ebx,word[scan_end+2]
		add	eax,2
%else
		mov	ebx,[scan_end]
%endif
;------------------------------------------------
		; In this loop:
		;   EAX = match_base2
		;   EBX = scan_end
		;   ECX = match_base
		;   EDX = limit or scan_start
		;   ESI = wmask|chain_length
		;   EDI = prev
		;   EBP = cur_match
%ifdef MATCH_DWORD1
		cmp	dword [ebp+eax],ebx	; check match end
%else
		cmp	word [ebp+eax],bx
%endif
		jnz	.long_loop
		mov	edx,[scan_start]
		cmp	dword [ebp+ecx],edx	; check match start (should check at least 3 bytes when offset <> 0)
		jz	.test_string
		xalign	4
.long_loop:
		mov	edx,[limit]
.long_loop2:
		and	ebp,esi			; really, BP &= SI (16 bits), but EBP.H==0 and 32-bit op is faster
		movzx	ebp,word [edi+ebp*2]
		cmp	ebp,edx			; limit
		jbe	.break_match
		sub	esi,0x10000
		js	.break_match
%ifdef MATCH_DWORD1
		cmp	dword [ebp+eax],ebx
%else
		cmp	word [ebp+eax],bx
%endif
		jnz	.long_loop2
		mov	edx,[scan_start]
		cmp	dword [ebp+ecx],edx
		jnz	.long_loop

;------------------------------------------------
		xalign	4
.test_string:
		; ECX = match_base
		; EBP = cur_match
		; ESI = chain|mask
		; EDI = prev
		mov	[chain_mask],esi

		mov	eax,[align_shift]
%define MAX_MATCH_A(x)  ((MAX_MATCH+(x-1)) & ~(x-1))
		mov	edx,-MAX_MATCH_A(8)
		mov	esi,[scan]
		lea	esi,[esi+eax+MAX_MATCH_A(8)] ; scan + align_shift + align(MAX_MATCH)
		lea	edi,[ebp+ecx]
		lea	edi,[edi+eax+MAX_MATCH_A(8)] ; cur_match + match_base + align(MAX_MATCH)
		mov	ebx,4

		xalign	4
.compare_loop:
		; EDX = negative loop valiable
		; ESI = scan
		; EBX = 4
		; ESI -> scan
		; EDI -> match
%rep 2
		mov	eax,[esi+edx]
		xor	eax,[edi+edx]
		jnz	.not_max_str
		add	edx,ebx			; edx += 4
%endrep
		js	.compare_loop		; loop while edx < 0
		; here strings are fully matched
.max_str:
		sub	ebp,[offset]
;??		cmp	ebp,[limit_base]	; need to check it here, because far_string+offset may be > limit
;??		jbe	.break_match
		mov	esi,[deflate_state]
		mov	[esi+DST.match_start],ebp
		mov	eax,MAX_MATCH
		jmp	.return
;------------------------------------------------
		xalign	4
.break_match:
		mov	eax,[best_len]
		mov	esi,[deflate_state]

.return:
		cmp	eax,[esi+DST.lookahead]
		jc	.ret
		mov	eax,[esi+DST.lookahead]
.ret:
		drop_vars
		pop	ebp,edi,esi,edx,ecx,ebx
		retn

;------------------------------------------------
.short_test2:
		mov	ebx,[scan_start]
		jb	.short_test		; best_len < 3
; here: best_len == 3  (need to find at least 4-byte match)
		; In this loop:
		;   EAX = 0x10000
		;   EBX = scan_start
		;   ECX = match_base
		;   EDX = limit
		;   ESI,EDI,EBP - as in long_loop
		cmp	[ebp+ecx],ebx
		je	.test_string
		mov	edx,[limit]
		mov	eax,0x10000
		xalign	4
.short_loop2:
		and	ebp,esi
		movzx	ebp,word [edi+ebp*2]
		cmp	ebp,edx			; limit
		jbe	.break_match
		sub	esi,eax
		js	.break_match
		cmp	[ebp+ecx],ebx
		jz	.test_string
		jmp	.short_loop2
;------------------------------------------------
; here: best_len == 2  (need to find at least 3-byte match)
; note: offset==0 (may be > 0 only after best_len > MIN_MATCH), so we can compare
;   only 1st 2 bytes to get correct result
.short_test:
		movzx	eax,word [ebp+ecx]
		xor	ax,bx
		jz	.test_string
		mov	edx,[limit]
		xalign	4
.short_loop:
		and	ebp,esi
		movzx	ebp,word [edi+ebp*2]
		cmp	ebp,edx			; limit
		jbe	.break_match
		sub	esi,0x10000
		js	.break_match
		movzx	eax,word [ebp+ecx]
		xor	ax,bx
		jz	.test_string
		jmp	.short_loop

;------------------------------------------------
		xalign	4
		; matches are smaller than MAX_MATCH
		; we've compared 32-bit integers, so we should check matches with smaller granularity
		; eax = last comparison result (XOR of match and scan)
.not_max_str:
		mov	edi,[prev]

%if 0
		; bsf is slow on P1 and PMMX
		; here: at least one of EAX bits non-zero
		bsf	ebx,eax			; EBX = number of 1st "1"-bit in EAX (starting from 0)
		shr	ebx,3
		lea	ecx,[esi+ebx]
		add	ecx,edx
%else
		test	eax, 0xFFFF
		jnz	.len_lower
		add	edx,2
		shr	eax,16
.len_lower:
		sub	al,1
		adc	edx,0
		lea	ecx,[esi+edx]
%endif

		mov	eax,ecx
		sub	eax,[scan]
		; ECX point to a 1st mismatched byte of scan
		; EBP = cur_match
		; EDI = prev
		; EAX = len
		cmp	eax,MAX_MATCH
		jge	.max_str
		cmp	eax,[best_len]
		jg	.match_is_longer

;------------------------------------------------
.continue:
		; cur_match = prev[cur_match & wsize]
		mov	esi,[chain_mask]
		and	ebp,esi
		movzx	ebp,word [edi+ebp*2]
.continue2:
		cmp	ebp,[limit]
		jbe	.break_match
		; if (--chain_length == 0) break
		sub	esi,0x10000
		js	.break_match
		jmp	.main_loop

;------------------------------------------------
		xalign	4
.match_is_longer:
		; here: len > best_len
		mov	edx,ebp			; EDX = cur_match-offset (used now and later)
		sub	edx,[offset]
;??		cmp	edx,[limit_base]	; need to check it here, because far_string+offset may be > limit
;??		jbe	.break_match
		mov	esi,[deflate_state]
		; s->match_start = cur_match - offset
		mov	[esi+DST.match_start],edx
		; if (len >= nice_match) break
		cmp	eax,[nice_match]
		jge	.return
		; best_len = len
		mov	[best_len],eax
		; update scan_end
		mov	ebx,[ecx-3]
		mov	[scan_end],ebx
		; match_base2 = match_base+len-3
		mov	ebx,[match_base]
		lea	ebx,[ebx+eax-3]
		mov	[match_base2],ebx

%ifdef ALWAYS_ZERO_OFFSET
		jmp	.continue
%endif
		; if (len <= MIN_MATCH ...
		cmp	eax,MIN_MATCH
		jle	.continue
		; ... || cur_match + len >= s->strstart) ...
		; NOTE: when max_chain_length is smaller than MIN_CHAIN_LEN, str_start=0 and this condition is always TRUE
		lea	ebx,[edx+eax]
		cmp	ebx,[str_start]
		; ... continue
		jae	.continue

;------------------------------------------------
		; Here:
		;   EAX = len
		;   EDX = cur_match-offset
		movzx	esi,word [chain_mask]	; get wmask (only)
		lea	ebx,[eax-MIN_MATCH]
		shl	ebx,16
		or	esi,ebx
		; EDX = next_pos = cur_match-offset
		; old_match = cur_match-offset
		mov	ebp,edx
		mov	eax,edx
		; ECX = limit
		mov	ecx,[limit_base]
		jmp	.scan_match_entry

		; Find a most distant hash chain, starting from current match.
		; NOTE: at least one of hash chains should be valid, even if
		;   string scan[0..len-1] contains unlinked chains (may appear
		;   when compressing in fast mode), because we have go here
		;   using valid hash chains

		; Loop parameters:
		;   EAX = old_match
		;   EBX = pos (var)
		;   ECX = limit
		;   EDX = next_pos
		;   ESI = wmask | (len-MIN_MATCH) << 16
		;   EDI = prev
		;   EBP = old_match+index
		xalign	4
.scan_match_loop:
		inc	ebp
		sub	esi,0x10000
		js	.scan_match_end		; whole string scanned

.scan_match_entry:
		and	ebp,esi
		movzx	ebx,word [edi+ebp*2]
		cmp	ebx,ecx
		jbe	.break_match		; one of chains either too far, or NIL
		inc	ecx			; update limit: limit = limit_base+i
		cmp	ebx,edx
		jnc	.scan_match_loop	; current chain is less distant than remembered
		mov	edx,ebx
		sub	ebp,eax			; offset = EBP-old_match
		mov	[offset],ebp		; NOTE: should mask offset with "wmask" later
		add	ebp,eax			; revert EBP value (add EAX back)
		jmp	.scan_match_loop

.scan_match_end:
		movzx	esi,si			; at this point ESI.H == 0xFFFF -- reset it
		; Try to check verify hash head at the end of current string, including one more byte,
		; to see if it points to longer distance than we have now.
		; Here:
		; EDX = next_pos
		; ESI = wmask
		; EDI = prev
		mov	ebp,[scan]
		add	ebp,[best_len]
		mov	ecx,[hash_shift]	; ECX = hash_shift
		movzx	eax,byte [ebp-MIN_MATCH+1]
		shl	eax,cl
		xor	al,[ebp-MIN_MATCH+2]
		shl	eax,cl
		xor	al,[ebp-MIN_MATCH+3]
		and	eax,[hash_mask]
		; EAX = hash
		mov	ebp,[hash_heads]
		; check head[hash]
		movzx	ebx,word [ebp+eax*2]	; EBX = hash_heads[hash]
		mov	eax,[best_len]		; compute offset to EAX
		sub	eax,MIN_MATCH-1
		mov	ecx,[limit_base]	; ECX = limit_base + offset
		add	ecx,eax
		cmp	ebx,ecx			; check limit
		jbe	.break_match
		cmp	ebx,edx
		jae	.comp_hash_skip		; this is not a better match
		mov	edx,ebx
		jmp	.set_offset
.comp_hash_skip:
		mov	eax,[offset]		; EAX = offset
.set_offset:
		and	eax,esi			; offset &= wmask
		; EAX = offset
		; EDX = new match
		mov	[offset],eax
		mov	ebx,[old_offset]
		sub	ebx,eax			; EBX = old_offset-offset
		mov	[old_offset],eax	; old_offset = offset
		; match_base[2] += (old_offset-offset);
		add	[match_base],ebx
		add	[match_base2],ebx
		; limit = limit_base + offset = limit - (old_offset-offset)
		sub	[limit],ebx
		; cur_match = next_pos
		mov	ebp,edx
		; ESI = chain_mask
		mov	esi,[chain_mask]
		jmp	.continue2

;------------------------------------------------------------------------------

		; Please do not remove this string!
		db 13,10,' Fast match finder for zlib, https://github.com/gildor2/fast_zlib ',13,10,0

;------------------------------------------------------------------------------


; Empty match_init() function

global match_init, _match_init

match_init:
_match_init:
		retn

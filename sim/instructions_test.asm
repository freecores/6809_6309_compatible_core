
; simple instruction excerciser

		ldd	#$AABB
		mul
		ldx	#$1234
		ldy	#$5678
		tfr	x,u	; 16 bit transfer
		tfr	a,u	; high to high
		tfr	b,u	
		tfr	x,a	; gets high byte
		tfr	x,b	; gets low byte


		lda	#$02
		ldb	#$00
		sta	$0
		stb	$1
		ldx	$0	; load saved value
		ldy	#$0
		cmpx	,y	; compare
		beq	test_push_pull

error:		bra	error

test_push_pull:	lds	#$00ff
		pshs	a,b
		puls	x
		cmpx	,y	; compare again
		bne	error

		bsr	test_bsr
		bne	error	; push/pull with sub don't work
		lbsr	test_lea
		bne	error
ok:		bra	ok

test_bsr:	pshs	y
		puls	y
		cmpx	0,y
		rts

test_lea:	leau	1,y
		leay	0,y
		rts

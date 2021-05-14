;;            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
;;                    Version 2, December 2004

;; Copyright (C) 2004 Craig Niles <niles.c@gmail.com >

;; Everyone is permitted to copy and distribute verbatim or modified
;; copies of this license document, and changing it is allowed as long
;; as the name is changed.

;;            DO WHAT THE FUCK YOU WANT TO PUBLIC LICENSE
;;   TERMS AND CONDITIONS FOR COPYING, DISTRIBUTION AND MODIFICATION

;;  0. You just DO WHAT THE FUCK YOU WANT TO.

;; Code for somewhat custom 6502 hardware.  Implements an I2C bus (i.e. bit-bangs) using 65C22 and uses that to
;; communicate with an MPC9808 temperature sensor. On startup, the LCD is configured and the MCP9808 woken up.
;; When an interrupt is triggered, e.g. via button press, the temperature (measured in celcius) is read and printed
;; to the display in decimal format.

PORTB = $6000
PORTA = $6001
DDRB = $6002
DDRA = $6003
T1CL = $6004
T1CH = $6005
T1LL = $6006
T1LH = $6007
T2CL = 6008
T2CH = 6009
SR = $600a
ACR = $600b
PCR = $600c
IFR = $600d
IER = $600e

E =  %10000000
RW = %01000000
RS = %00100000

SCL = %00000001
SDA = %00000010

TS_ADDR = %00001100
I2C_R = %10000000
ATR = %10100000
CR = %10000000

tmp = $0010			; 2 bytes
value = $0200			; 2 bytes
divisor = $0202			; 2 bytes
mod10 = $0204			; 2 bytes
chrbuf = $0206			; 6 bytes
time_counter = $020c		; 1 byte
time = $020d			; 1 byte

 	.org $8000

inc_time:

print_dec:
	lda #10
	ldx #0
	sta divisor
div10:	jsr divide
	lda mod10
	clc
	adc #"0"
	pha
	inx
	lda value
	ora value + 1
	bne div10
printloop:
	pla
	jsr print_char
	dex
	bne printloop

	rts

;;; 16x8 division
;;; dividend and result are stored in value.  the divisor is stored in divisor
divide:
	phx
	lda #0
	sta mod10
	sta mod10 + 1
	clc

	ldx #16
divloop:
	rol value
	rol value + 1
	rol mod10
	rol mod10 + 1

	sec
	lda mod10
	sbc divisor
	tay
	lda mod10 + 1
	sbc #0
	bcc ignore_result
	sty mod10
	sta mod10 + 1

ignore_result:
	dex
	bne divloop
	rol value
	rol value + 1
	plx
	rts

lcd_wait:
	pha
	lda #%00000000 		; Set all pins on port B to input
	sta DDRB
lcd_busy:
	lda #RW
	sta PORTA
	lda #(RW | E)
	sta PORTA
	lda PORTB
	and #%10000000
	bne lcd_busy
	lda #RW
	sta PORTA
	lda #%11111111 		; Set all pins on port B to output
	sta DDRB
	pla
	rts

lcd_instruction:
	jsr lcd_wait
	sta PORTB
	lda #0
	sta PORTA
	lda #E
	sta PORTA		; set enable to bit to send command to LCD
	lda #0
	sta PORTA
	rts

print_hex:
	pha
	lsr
	lsr
	lsr
	lsr
	tax
	lda hextable,x
	jsr print_char
	pla
	and #$0f
	tax
	lda hextable,x
	jsr print_char
	rts

print_char:
	jsr lcd_wait
	sta PORTB
	lda #RS
	sta PORTA
	lda #(RS | E)
	sta PORTA		; set enable to bit to send command to LCD
	lda #RS
	sta PORTA
	rts

i2c_start:
	;; send start condition
	lda #(SDA | SCL) 	; clock and data high
	sta PORTA
	lda #(SCL) 		; clock high, data low
	sta PORTA

	lda #0
	sta PORTA		; clock low, data low
	rts

i2c_stop:
	;; send stop condition
	lda #(SCL)		; clock high
	nop
	sta PORTA
	lda #(SCL | SDA)	; clock high; data high
	sta PORTA
	rts

;;; Clock out up to 8 bits to I2C. Direction register must be set correctly before calling.
;;; Inputs:
;;; a - data to send
;;; x - number of bits
i2c_send:
	pha
	and #1
	asl a
	sta PORTA 		; data high/low, clock low

	ora #SCL
	sta PORTA		; clock high

	eor #SCL
	sta PORTA		; clock low

	lda #0
	sta PORTA		; clock and data low

	pla
	lsr a			; discard leading bit
	dex
	bne i2c_send		; more bits to send
	rts

;;; Rotates up to 8 bits from I2C into a register.  Direction register must be set correctly before calling
;;; Inputs:
;;; x - number of bits to read
;;; Outputs:
;;; a result of reading from i2c
i2c_read:
	pha			; save value of a
i2c_read_more:
	lda #SCL
	sta PORTA		; clock high

	lda PORTA 		; read SDA
	lsr a
	lsr a			; move SDA into carry
	pla
	rol			; rotate SDA onto result
	pha			; save result on stack

	lda #0
	sta PORTA		; clock low

	dex
	bne i2c_read_more
	pla			; pull result from stack into a
	rts

i2c_ack:
	lda #%11100001		; set SDA to input
	sta DDRA

	ldx #1			; read one bit, shifted into a
	lda #0
	jsr i2c_read
	pha 			; save the value

	lda #%11100011		; set SDA back to output
	sta DDRA

	pla 			; result should be zero if we received an ACK
	rts

mcp9808_wake:
	lda #%11100011
	sta DDRA

	jsr i2c_start

	ldx #8
	lda #(TS_ADDR)
	jsr i2c_send

	jsr i2c_ack
	bne noack_wake

	ldx #8
	lda #CR
	jsr i2c_send

	jsr i2c_ack
	bne noack_wake

	ldx #8
	lda #0
	jsr i2c_send

	jsr i2c_ack
	bne noack_wake

	ldx #8
	lda #0
	jsr i2c_send

	jsr i2c_ack
	bne noack_wake

	jsr i2c_stop

noack_wake:

	lda #%11100000
	sta DDRA
	rts

print_prompt:
	lda #%00000001		; clear screen
	jsr lcd_instruction
	ldx 0
next_char:
	lda prompt,x
	beq done_print
	jsr print_char
	inx
	jmp next_char
done_print:
	rts

;;;  Read temperature from I2C device and write result to lcd
print_temp:
	lda #(SDA | SCL)
	sta PORTA

	lda #%11100011
	sta DDRA

	jsr i2c_start

	ldx #8
	lda #(TS_ADDR)	; send slave address and enable write
	jsr i2c_send

	jsr i2c_ack
	bne noack

	ldx #8
	lda #ATR		; write address of temp register
	jsr i2c_send

	jsr i2c_ack
	bne noack

	jsr i2c_stop
	jsr i2c_start

	ldx #8
	lda #(TS_ADDR | I2C_R) 		; start read
	jsr i2c_send

	jsr i2c_ack
	bne noack

	lda #%11100001		; set SDA to input
	sta DDRA

	ldx #8
	lda #0
	jsr i2c_read		; read 8 bits from i2c
	pha

	lda #%11100011		; set SDA to output
	sta DDRA

	ldx #1
	lda #0
	jsr i2c_send 		; send ack

	lda #%11100001		; set SDA to input
	sta DDRA

	ldx #8
	lda #0
	jsr i2c_read		; read 8 bits from i2c
	pha

	lda #%11100011		; set SDA to output
	sta DDRA

	ldx #1
	lda #1
	jsr i2c_send 		; send NAK

	jsr i2c_stop

	pla
	lsr 			; divide by 16
	lsr
	lsr
	lsr
	sta tmp

	pla
	and #$1f		; clear flags
	asl			;  multiply by 16
	asl
	asl
	asl

	cld
	clc
	adc tmp			; add the results

	sta value		; store in value

	lda #0
	sta value + 1

	jsr print_dec

noack:
	lda #"c"		; print c
	jsr print_char
	lda #%11100000
	sta DDRA
	rts

reset:
	ldx  #$ff 		; initialize stack pointer
	txs
	cli 			; enable interrupts

	lda #$c2 		; set up interrupt control on interface controller
	sta IER
	lda #$00
	sta PCR

	;; set up interface controller ports
	lda #%11111111 		; Set all pins on port B to output
	sta DDRB
	lda #%11100000 		;
	sta DDRA

	lda #(SDA | SCL)	; sda and scl should be high, to begin with
	sta PORTA

	;; set up LCD
	lda #%00111000 		; Set 8-bit mode 2-line mode 5x8 font
	jsr lcd_instruction
	lda #%00001110 		; Display on; cursor on; blink off
	jsr lcd_instruction
	lda #%00000110 		; Increment and shift cursor; don't shift display
	jsr lcd_instruction

	jsr print_prompt
	jsr mcp9808_wake

	stz time
	lda #20
	sta time_counter
	lda #%01000000
	sta ACR
	lda #$50		; set T1 timer latch and counter to 50,000
	sta T1CL
	lda #$C3
	sta T1LH
	sta T1CH

loop:
	jmp loop

number:	 .word 1729

prompt:
	;; 0-40 char first line, 41-80 second line
	.asciiz ">> "

hextable:
	.asciiz "0123456789ABCDEF"

nmi:
irq:
	dec time_counter
	bne cont
	lda #20
	sta time_counter
	inc time
	jsr print_prompt
	jsr print_temp

	lda time
	sta value
	stz value + 1
	jsr print_dec
cont:
	bit PORTA
	bit T1CL
	rti

	.org $fffa
	.word nmi
	.word reset
	.word irq

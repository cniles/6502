PORTB = $6000 
PORTA = $6001
DDRB = $6002
DDRA = $6003
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
	
counter = $0200 		; bytes

	.org $8000

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

reset:
	ldx  #$ff 		; initialize stack pointer
	txs
	cli 			; enable interrupts

	lda #$82 		; set up interrupt control on interface controller
	sta IER
	lda #$00
	sta PCR

	;; set up interface controller for lcd
	lda #%11111111 		; Set all pins on port B to output
	sta DDRB
	lda #%11100011 		; Set top 3 and bottom 2 pins on port A to output
	sta DDRA

	;; set up LCD
	lda #%00111000 		; Set 8-bit mode 2-line mode 5x8 font
	jsr lcd_instruction
	lda #%00001110 		; Display on; cursor on; blink off
	jsr lcd_instruction
	lda #%00000110 		; Increment and shift cursor; don't shift display
	jsr lcd_instruction

	lda #%00000001
	jsr lcd_instruction

	ldx 0
print_prompt:
	lda message,x
	beq done_print
	jsr print_char
	inx
	jmp print_prompt
done_print:

;;; Try to get I2C slave to ack
	jsr i2c_start

	ldx #8
	lda #(TS_ADDR)	; send slave address and enable write
	jsr i2c_send

	lda #%11100001		; set SDA to input
	sta DDRA

	ldx #1			; read one bit, shifted into a
	lda #0
	jsr i2c_read
	pha 			; save the value

	lda #%11100011		; set SDA back to output
	sta DDRA

	pla 			; result should be zero if we received an ACK
	bne noack
	lda #"A"		; print A for acknowledge

	ldx #8
	lda #%11111111		; set temperature register
	jsr i2c_send

	
	


	jsr print_char
noack:
	lda #"."		; print that i2c finished
	jsr print_char
loop:	
	jmp loop

message:
	;; 0-40 char first line, 41-80 second line
	.asciiz ">> "

nmi:
irq:
	lda #"!"
	jsr print_char
	bit PORTA
	rti

	.org $fffa
	.word nmi
	.word reset
	.word irq

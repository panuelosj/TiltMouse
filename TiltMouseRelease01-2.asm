;**********************************************************************
;																		*
;	Filename:		AAA Tilt Mouse Release1,2.asm						*
;	Date:																*
;	File Version:	1.2.0												*
;																		*
;	Author:			Jonathan											*
;	Company:															*
;																		* 
;																		*
;**********************************************************************
;																		*
;	Files Required:	P16F690.INC											*
;																		*
;**********************************************************************
;																		*
;	Notes:																*
;		button stat: 	hardware, 0=pressed								*
;						software vars, 1=unpressed						*
;																		*
;**********************************************************************
;																		*
;	Microsoft Serial Mouse Protocol:									*
;		Data in 3-byte packets											*
;																		*
;		Bit:		7	6	5	4	3	2	1	0						*
;		Byte0:		1	1	LB	RB	Y7	Y6	X7	X6						*
;		Byte1:		1	0	X5	X4	X3	X2	X1	X0						*
;		Byte2:		1	0	Y5	Y4	Y3	Y2	Y1	Y0						*
;																		*
;																		*
;		Initialized by sending ASCII 'M' when RTS toggled				*
;**********************************************************************


	list		p=16f690		; list directive to define processor
	#include <p16F690.inc>
	
	#define		iTiltX		PORTA,1		;pin names
	#define		iTiltY		PORTA,0
	#define		iRightB		PORTA,4
	#define		iLeftB		PORTA,3
	#define		iRightP		PORTC,1
	#define		iLeftP		PORTC,0
	#define		iSensTog	PORTA,5
	#define		RTS			PORTB,4
	
	#define		nOffset		.83
	#define		nUpperBound	.86
	#define		nLowerBound	.80
	#define		nShiftCtrl	.250
	
	#define		sOffset		.16			;previously .22
	#define		sUpperBound	.16			;			.24
	#define		sLowerBound	.16			;			.20
	#define		sShiftCtrl	.220		;			.230
	
	
	__config (_INTRC_OSC_NOCLKOUT & _WDT_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _BOR_OFF & _IESO_OFF & _FCMEN_OFF)


	cblock 0x20
Delay1						; unused delay variables
Delay2

VarTx						; temporary holder for data to transmit
VarRc						; temporary holder for data received

xRaw						; raw values from tilt sensor, thrown out
yRaw
xRawH						; high bits from tilt sensor, used
yRawH
xMov						; change in direction, sent to USB
yMov

offset						; 0 degrees
upperBound					; for deadzone (offset + x degs)
lowerBound					; for deadzone (offsel - x degs)
shiftCtrl					; for changing sensitivity 

;---------------------------------------------------------------------
;	Mouse Packet Data
;---------------------------------------------------------------------
Byte0
Byte1	
Byte2
Byte3	
	endc
	
	org 0x0
	goto		Start

Start:	
	;-----------------------------------------------------------------
	; SET CONSTANTS
	;-----------------------------------------------------------------
	movlw		.83
	movwf		offset						; set as middle (this binary out becomes 0)
	movlw		.87
	movwf		upperBound					; deadzone - between lowerBound and upperBound
	movlw		.79
	movwf		lowerBound	
	movlw		.250
	movwf		shiftCtrl
	
	
	;-----------------------------------------------------------------
	; SET CPU SPEED			111 = 8MHz
	;
	;	111 = 8MHz; 110 = 4MHz; 101 = 2MHz; 100 = 1MHz
	;-----------------------------------------------------------------
	banksel		OSCCON						
	bcf			OSCCON, IRCF0				
	bsf			OSCCON, IRCF1				
	bsf			OSCCON, IRCF2				
	
	
	;-----------------------------------------------------------------
	; SET IO Pins
	;-----------------------------------------------------------------
	banksel		TRISA
	clrf		TRISA
	clrf		TRISB
	clrf		TRISC
	bsf			TRISA, 1					; Tilt Sensor X
	bsf			TRISA, 0					; Tilt Sensor Y
	bsf			TRISA, 3					; Right Button
	bsf			TRISA, 4					; Left Button
	bsf			TRISA, 5					; sensitivity toggle
	bsf			TRISC, 0					; pressure sensor 1
	bsf			TRISC, 1					; pressure sensor 2
	bsf			TRISB, 4					; RTS: Request to send from PC
	
	
	;-----------------------------------------------------------------
	; SET EUSART Comms			Asynchronous
	;-----------------------------------------------------------------
	banksel		TRISB
	bsf			TRISB, 5
	bsf			TRISB, 6
	bsf			TRISB, 7
		
	banksel		TXSTA			; Transmitter Config
	bcf			TXSTA, TX9			; 9-bit Transmit:			Disabled
	bsf			TXSTA, TXEN			; Transmit Enable: 			Enabled
	bcf			TXSTA, SYNC			; EUSART Mode Select: 0=asynchronous
	bcf			TXSTA, SENB			; Send Break Character bit
	bsf			TXSTA, BRGH			; High Baud Rate Select Bit
	
	banksel		RCSTA			; Receiver Config
	bsf			RCSTA, SPEN			; Serial Port Enable
	bcf			RCSTA, RX9			; 9-bit Receive:			Disabled
	bsf			RCSTA, CREN			; Receive Enable:			Enabled
	
	banksel		BAUDCTL			; Baud Rate Generator
	bcf			BAUDCTL, SCKP		; Synchronous Transmit:		Disabled
	bcf			BAUDCTL, BRG16		; 16-bit baud rate gen:		Disabled
	bcf			BAUDCTL, WUE		; Wake-up Enable:			Disabled
	banksel		SPBRG
	movlw		.207
	movwf		SPBRG				; 1200 Hz @ 8-bit, high rate
	movlw		.0
	movwf		SPBRGH
	
	;-----------------------------------------------------------------
	; INTERRUPTS					Turn Everything Off
	;-----------------------------------------------------------------
	banksel		PIE1
	clrf		PIE1
	clrf		PIE2
	bsf			PIE1, TXIE			; Transmitter Interrupt
	bsf			PIE1, RCIE			; Receiver Interrupt
	banksel		INTCON
	clrf		INTCON
	bsf			INTCON, PEIE		; Peripheral Interrupts Enabled
	bcf			INTCON, GIE			; Global Interrupt Disabled
	
	;-----------------------------------------------------------------
	; SET A-D Converter				Turn Everything Off
	;-----------------------------------------------------------------
	banksel		ADCON0						
	clrf		ADCON0				
	banksel		ANSEL
	clrf		ANSEL
	clrf		ANSELH
	
	;-----------------------------------------------------------------
	; CLEAR Ports					Turn Everything Off
	;-----------------------------------------------------------------
	banksel		PORTA
	clrf		PORTA
	clrf		PORTC
	clrf		PORTB

	;-----------------------------------------------------------------
	; Code Pointer
	;-----------------------------------------------------------------
	goto		Main
	
Main:
	btfsc		RTS						; initialize as "Microsoft Mouse" when asked by PC-side driver
	call		MouseReboot
		
	;-----------|X AXIS|----------------------------------------------
	call		ReadX					; read tilt sensor for raw data
	call		SubtrX					; do math to fix data
	;-----------|Y AXIS|----------------------------------------------
	call		ReadY					; read tilt sensor for raw data
	call		SubtrY					; do math to fix data
	
	
	;-----------|BYTE 0 of PACKET - Direction + Button States|--------
	movlw		b'11000000'				; bit 6&7 synchronizes UART clock
	movwf		Byte0
	btfsc		xMov, 6					; move highest two bits of x here
	bsf			Byte0, 0
	btfsc		xMov, 7
	bsf			Byte0, 1
	btfsc		yMov, 6					; move highest two bits of y here
	bsf			Byte0, 2
	btfsc		yMov, 7
	bsf			Byte0, 3
	
	bcf			Byte0, 4
	bcf			Byte0, 5
	btfsc		iRightB					; right mouse button
	bsf			Byte0, 4
	btfsc		iLeftB					; left mouse button
	bsf			Byte0, 5
	btfsc		iRightP					; right pressure sensor
	bsf			Byte0, 4
	btfsc		iLeftP					; left pressure sensor
	bsf			Byte0, 5
	;-----------|BYTE 2 of PACKET - X MAGNITUDE|----------------------
	bsf			xMov, 7					; bit 6&7 synchronizes UART clock
	bcf			xMov, 6
	movf		xMov, w
	movwf		Byte1
	;-----------|BYTE 3 of PACKET - Y MAGNITUDE|----------------------
	bsf			yMov, 7					; bit 6&7 synchronizes UART clock
	bcf			yMov, 6
	movf		yMov, w
	movwf		Byte2
	
	
	;-----------|UART TRANSMIT DATA|----------------------------------
	movf		Byte0, w
	movwf		VarTx
	call		Transmit				
	movf		Byte1, w
	movwf		VarTx
	call		Transmit				
	movf		Byte2, w
	movwf		VarTx
	call		Transmit				
	
	
	;-----------|SENSITIVITY TOGGLE|----------------------------------
		movlw		nOffset				; set values depending on toggle
		movwf		offset
		movlw		nUpperBound
		movwf		upperBound
		movlw		nLowerBound
		movwf		lowerBound
		movlw		nShiftCtrl
		movwf		shiftCtrl
	btfsc		iSensTog
	goto		$+9
		movlw		sOffset
		movwf		offset
		movlw		sUpperBound
		movwf		upperBound
		movlw		sLowerBound
		movwf		lowerBound
		movlw		sShiftCtrl
		movwf		shiftCtrl	
	
	goto		Main				
	;-----------|INFINITE LOOP|---------------------------------------	
	
MouseReboot:
	btfss		RTS							; restart protocol
	goto		$-1
	call		MouseInit
	return
MouseInit:
	movlw		'M'							; emulate Microsoft Mouse
	movwf		VarTx
	call		Transmit
	return



;-----------------------------------------------------------------
; Sensor Check			
;-----------------------------------------------------------------
ReadX:
		; Buffer
	btfsc		iTiltX					; Wait for Tilt Sensor to go low
	goto		$-1
	btfss		iTiltX					; Wait for Tilt Sensor to go high
	goto		$-1
	clrf		xRaw					
	clrf		xRawH
		; Counter
	incf		xRaw, f					; count until the sensor output goes low (measure duty cycle)
	btfsc		STATUS, Z				
	call		IncrXHigh				
	btfsc		iTiltX					
	goto		$-4
	return
IncrXHigh:
	incf		xRawH, f
	movf		shiftCtrl, w			; low bits shift control (to move more significant bits to higher variable)
	movwf		xRaw
	return
SubtrX:
	clrf		xMov					; set x change to 0, for use with dead-zone
	movf		xRawH, w				
	subwf		upperBound, w			; test if value > upperBound
	btfsc		STATUS, C				; C = 0 when W > f, aka value > upperBound
	goto		$+4
		movf		upperBound, w
		subwf		xRawH, w
		movwf		xMov	
	movf		lowerBound, w
	subwf		xRawH, w				; test if value < lowerBound
	btfss		STATUS, C				; C = 0 when W > f, aka value < lowerBound
		movwf		xMov
	return



ReadY:
		; Buffer
	btfsc		iTiltY					; Wait for Tilt Sensor to go low
	goto		$-1
	btfss		iTiltY					; Wait for Tilt Sensor to go high
	goto		$-1
	clrf		yRaw					
	clrf		yRawH
		; Counter
	incf		yRaw, f					; count until the sensor output goes low (measure duty cycle)
	btfsc		STATUS, Z				
	call		IncrYHigh				
	btfsc		iTiltY					
	goto		$-4
	return
IncrYHigh:
	incf		yRawH, f
	movf		shiftCtrl, w			; low bits shift control (to move significant bits to higher variable)
	movwf		yRaw
	return
SubtrY:
	clrf		yMov					; set y change to 0, for use with dead-zone
	movf		yRawH, w				
	subwf		upperBound, w			; test if value > upperBound
	btfsc		STATUS, C				; C = 0 when W > f, aka value > upperBound
	goto		$+4
		movf		upperBound, w
		subwf		yRawH, w
		movwf		yMov	
	
	movf		lowerBound, w
	subwf		yRawH, w				; test if value < lowerBound
	btfss		STATUS, C				; C = 0 when W > f, aka value < lowerBound
		movwf		yMov	
	return


;-----------------------------------------------------------------
; Polling				Non-interrupt based status checking
;-----------------------------------------------------------------
Transmit:
	banksel		TXREG
	btfss		PIR1, TXIF
	goto		$-1
	movf		VarTx, w
	movwf		TXREG
	return
	
Receive:
	banksel		RCREG
	movf		RCREG, w
	movwf		VarRc
	return
Delay:
	decfsz		Delay1,f			
	goto		Delay				
	decfsz		Delay2,f			
	goto		Delay					
	return

	end


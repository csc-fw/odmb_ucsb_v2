`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: The Ohio State University
// Engineer: Ben Bylsma
// 
// Create Date:    11:48:23 03/12/2013 
// Design Name: 
// Module Name:    BPI_PORT 
// Project Name:   ODMB
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//  VME commands for BPI interface
//  Address  Command   Description
//  -----------------------------------
//  0x04010      4     Control Register 
//  0x04014      5     Read Test Configuration Register
//  0x04018      6     Upload Configuration Registers from the Flash PROM
//  0x0401C      7     Download Configuration Registers in the Flash PROM
//  0x04020      8     Reset BPI interface state machines (no data)
//  0x04024      9     Disable parsing commands in the command FIFO (while filling FIFO with commands) (no data)
//  0x04028     10     Enable parsing commands in the command FIFO (no data)
//  0x0402C     11     Write one word to command FIFO (16 bits)
//  0x04030     12     Read one word from readback FIFO (16 bits)
//  0x04034     13     Read word count of words remaining in readback FIFO (11 bits)
//  0x04038     14     Read BPI interface status register (16 bits)
//  0x0403C     15     Read timer low order bits 15:0
//  0x04040     16     Read timer high order bits 31:16
//////////////////////////////////////////////////////////////////////////////////

module BPI_PORT(
	input CLK,                       // 40MHz clock
	input RST,                       // system reset
	 // VME selection/control
	input DEVICE,                    // 1 bit indicating this device has been selected
	input STROBE,                    // Data strobe synchronized to rising or falling edge of clock and asynchronously cleared
	input [9:0] COMMAND,             // command portionn of VME address
	input WRITE_B,                   // read/write_bar
	input [15:0] INDATA,             // data from VME writes to be provided to BPI interface
	output reg [15:0] OUTDATA,           // data from BPI interface to VME buss for reads
	output DTACK_B,                  // DTACK bar
    // BPI controls
	output reg BPI_RST,                  // Resets BPI interface state machines
	output reg [15:0] BPI_CMD_FIFO_DATA, // Data for command FIFO
	output reg BPI_WE,                   // Command FIFO write enable  (pulse one clock cycle for one write)
	output reg BPI_RE,                   // Read back FIFO read enable  (pulse one clock cycle for one read)
	output reg BPI_DSBL,                 // Disable parsing of BPI commands in the command FIFO (while being filled)
	output reg BPI_ENBL,                 // Enable  parsing of BPI commands in the command FIFO
	output reg BPI_CFG_DL,                 // Download Configuration Regs in Flash PROM
	output reg BPI_CFG_UL,                 // Upload Configuration Regs from Flash PROM
	input [15:0] BPI_RBK_FIFO_DATA,  // Data on output of the Read back FIFO
	input [10:0] BPI_RBK_WRD_CNT,    // Word count of the Read back FIFO (number of available reads)
	input [15:0] BPI_STATUS,         // FIFO status bits and latest value of the PROM status register. 
	input [31:0] BPI_TIMER,           // General timer
// Guido - Aug 26
	output reg BPI_MODE,                 // 0 -> FILL PROM with CFG_REG values, 1 -> FILL PROM from VME
	output reg BPI_CFG_DATA_SEL,         // CFG_REG values into PROM: 0 -> constants stored in CFG_CONTROLLER, 1 -> CFG_REG values
	input [15:0] BPI_CFG_REG0,        
	input [15:0] BPI_CFG_REG1,        
	input [15:0] BPI_CFG_REG2,        
	input [15:0] BPI_CFG_REG3        
);

wire active_write;
wire active_read;
reg  dtack;
wire busy;
reg  busy_1;
reg  busy_2;
wire lead_0;
reg  lead_1;
wire trail_0;

// Guido - Aug 26
reg BPI_CTRL_REG_WE;
reg [1:0] BPI_CFG_REG_SEL;

assign DTACK_B = (busy || busy_2) ? ~dtack : 1'bz;
assign busy    = (DEVICE && STROBE);
assign active_write = (DEVICE && !WRITE_B);
assign active_read  = (DEVICE && WRITE_B);
assign lead_0 = busy && !busy_1;
assign trail_0 = !busy && busy_1;

always @(posedge CLK or posedge RST)
begin
//	if(RST)
//		OUTDATA <= 16'h0000;
//	else
//		if(active_read && lead_0)
//			case(COMMAND)
//				10'h00C :                        // VME address 0x04030; command 12 -- Read one word from readback FIFO
//					OUTDATA <= BPI_RBK_FIFO_DATA;
//				10'h00D :                        // VME address 0x04034; command 13 -- Read words left in readback FIFO
//					OUTDATA <= {5'b00000,BPI_RBK_WRD_CNT};
//				10'h00E :                        // VME address 0x04038; command 14 -- Read interface status register
//					OUTDATA <= BPI_STATUS;
//				10'h00F :                        // VME address 0x0403C; command 15 -- Read timer, low order
//					OUTDATA <= BPI_TIMER[15:0];
//				10'h010 :                        // VME address 0x04040; command 16 -- Read timer, high order
//					OUTDATA <= BPI_TIMER[31:16];
//				default :
//					OUTDATA <= 16'h0000;
//			endcase
//		else
//			OUTDATA <= OUTDATA;
//end
	if(RST)
		OUTDATA <= 16'h0000;
	else
			case(COMMAND)
// Guido - Aug 26
				10'h005 :                        // VME address 0x04014; command 5 -- Read Test CFG Registers
					case (BPI_CFG_REG_SEL)
					  2'b00 : OUTDATA <= BPI_CFG_REG0; 
					  2'b01 : OUTDATA <= BPI_CFG_REG1; 
					  2'b10 : OUTDATA <= BPI_CFG_REG2; 
					  2'b11 : OUTDATA <= BPI_CFG_REG3; 
					  default : OUTDATA <= 16'h0000;
					endcase
				10'h00C :                        // VME address 0x04030; command 12 -- Read one word from readback FIFO
					OUTDATA <= BPI_RBK_FIFO_DATA;
				10'h00D :                        // VME address 0x04034; command 13 -- Read words left in readback FIFO
					OUTDATA <= {5'b00000,BPI_RBK_WRD_CNT};
				10'h00E :                        // VME address 0x04038; command 14 -- Read interface status register
					OUTDATA <= BPI_STATUS;
				10'h00F :                        // VME address 0x0403C; command 15 -- Read timer, low order
					OUTDATA <= BPI_TIMER[15:0];
				10'h010 :                        // VME address 0x04040; command 16 -- Read timer, high order
					OUTDATA <= BPI_TIMER[31:16];
				default :
					OUTDATA <= 16'h0000;
			endcase
end
always @(posedge CLK or posedge RST)
begin
	if(RST)
		BPI_CMD_FIFO_DATA <= 16'h0000;
	else
		if(active_write && lead_0)
			case(COMMAND)
				10'h00B :                        // VME address 0x0402C; command 11 -- Write one word to command FIFO
					BPI_CMD_FIFO_DATA <= INDATA;
				default :
					BPI_CMD_FIFO_DATA <= 16'h0000;
			endcase
		else
			BPI_CMD_FIFO_DATA <= BPI_CMD_FIFO_DATA;
end



always @(posedge CLK)
begin
	busy_1 <= busy;
	busy_2 <= busy_1;
	lead_1 <= lead_0;
	BPI_RST <= lead_0 && (COMMAND == 10'h008);
	BPI_DSBL <= lead_0 && (COMMAND == 10'h009);
	BPI_ENBL <= lead_0 && (COMMAND == 10'h00A);
	BPI_WE <= lead_0 && (COMMAND == 10'h00B);
	BPI_RE <= lead_0 && (COMMAND == 10'h00C);
// Guido - Aug 26
	BPI_CTRL_REG_WE <= lead_0 && (COMMAND == 10'h004);
	BPI_CFG_UL <= lead_0 && (COMMAND == 10'h006);
	BPI_CFG_DL <= lead_0 && (COMMAND == 10'h007);
end

// Guido - Aug 26
always @(posedge BPI_CTRL_REG_WE or posedge RST)
begin
  if (RST)
	   BPI_MODE <= 1'b0;
	else
	   BPI_MODE <= INDATA[3];
end

always @(posedge BPI_CTRL_REG_WE or posedge RST)
begin
  if (RST)
	   BPI_CFG_DATA_SEL <= 2'b00;
	else
	   BPI_CFG_DATA_SEL <= INDATA[2];
end

always @(posedge BPI_CTRL_REG_WE or posedge RST)
begin
  if (RST)
	   BPI_CFG_REG_SEL <= 2'b00;
	else
	   BPI_CFG_REG_SEL <= INDATA[1:0];
end

always @(posedge CLK or posedge RST)
begin
	if(RST)
		dtack <= 1'b0;
	else
		if((active_read && lead_1) || (active_write && lead_0))
			dtack <= 1'b1;
		else if(trail_0)
			dtack <= 1'b0;
		else
			dtack <= dtack;
end


endmodule

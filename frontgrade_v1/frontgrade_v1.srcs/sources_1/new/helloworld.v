//`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 01:03:24 PM
// Design Name: 
// Module Name: helloworld
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//`ifndef	VERILATOR
//`define OPT_STANDALONE
//`endif

`default_nettype none

module helloworld #(
    parameter CLK_FREQ = 200_000_000,
    parameter BAUD = 115200,
    parameter [30:0] INITIAL_UART_SETUP = CLK_FREQ / BAUD
    )(
    input  wire sysclk_p,
    input  wire sysclk_n,
    output wire [7:0] led,
    //`ifndef	OPT_STANDALONE
	//input	wire	[30:0]	i_setup,
    //`endif
	output	wire		o_uart_tx
    );

// Signal declaration
reg	[7:0]   message	[0:15];
reg		    pwr_reset;
reg	[27:0]	counter;
reg	[7:0]   r_led;

reg	    	tx_stb;
reg	[3:0]	tx_index;
reg	[7:0]	tx_data;

wire		tx_break, tx_busy;
wire		cts_n;
wire	[30:0]	i_setup;

// Differential clk set up
wire clk_buff;
wire i_clk;

IBUFDS #(
   .DIFF_TERM("FALSE"),       // Differential Termination
   .IBUF_LOW_PWR("TRUE"),     // Low power="TRUE", Highest performance="FALSE"
   .IOSTANDARD("DEFAULT")     // Specify the input I/O standard
) IBUFDS_inst (
   .O(clk_buff),  // Buffer output
   .I(sysclk_p),  // Diff_p buffer input (connect directly to top-level port)
   .IB(sysclk_n) // Diff_n buffer input (connect directly to top-level port)
);

BUFG BUFG_inst (
   .O(i_clk), // 1-bit output: Clock output
   .I(clk_buff)  // 1-bit input: Clock input
);


//`ifdef	OPT_STANDALONE
assign i_setup = INITIAL_UART_SETUP;
assign led = r_led;
//`endif    
always @(posedge i_clk) 
    r_led <= 8'hAA;


// pwr_reset
initial	pwr_reset = 1'b1;
always @(posedge i_clk)
    pwr_reset <= 1'b0;
	// Initialize the message
	initial begin
		message[ 0] = "H";
		message[ 1] = "e";
		message[ 2] = "l";
		message[ 3] = "l";
		message[ 4] = "o";
		message[ 5] = ",";
		message[ 6] = " ";
		message[ 7] = "W";
		message[ 8] = "o";
		message[ 9] = "r";
		message[10] = "l";
		message[11] = "d";
		message[12] = "!";
		message[13] = " ";
		message[14] = 8'h0D;   // carriage return (CR)
		message[15] = 8'h0A;   // line feed (LF)
	end


	// Send a Hello World message to the transmitter
	initial	counter = 28'hffffff0; // 16 last
	always @(posedge i_clk)
		counter <= counter + 1'b1;

	assign	tx_break = 1'b0;
	
	initial	tx_index = 4'h0;
	always @(posedge i_clk)
        if ((tx_stb)&&(!tx_busy))
            tx_index <= tx_index + 1'b1;
    // sending
	always @(posedge i_clk)
		tx_data <= message[tx_index];

	initial	tx_stb = 1'b0;
	always @(posedge i_clk)
        if (&counter)
            tx_stb <= 1'b1;
        else if ((tx_stb)&&(!tx_busy)&&(tx_index==4'hf))
            tx_stb <= 1'b0;

	// The UART transmitter
	// Bypass any hardware flow control
	assign	cts_n = 1'b0;

//`ifdef	USE_LITE_UART
//	txuartlite
//		#(24'd868)
//		transmitter(i_clk, tx_stb, tx_data, o_uart_tx, tx_busy);
//`else
uart_tx transmitter (
    .i_clk     (i_clk),
    .i_reset   (pwr_reset),
    .i_break   (tx_break),
    .i_wr      (tx_stb),
    .i_setup   (i_setup),
    .i_data    (tx_data),
    .i_cts_n   (cts_n),
    .o_uart_tx (o_uart_tx),
    .o_busy    (tx_busy)
);
//`endif    
    
endmodule

//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Mariana MM
// 
// Create Date: 09/17/2026 02:12:28 PM
// Design Name: 
// Module Name: uart_rx
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments: Based on ZipCPU's rxuart.v with some modifications
// 
//////////////////////////////////////////////////////////////////////////////////

`default_nettype    none

module uart_rx #(
    parameter CLK_FREQ = 200_000_000,
    parameter BAUD = 115200,
    localparam [30:0] INITIAL_SETUP = CLK_FREQ / BAUD, 
    localparam [3:0] RXU_BIT_ZERO    =   4'h0,
                     RXU_BIT_ONE     =   4'h1,
                     RXU_BIT_TWO     =   4'h2,
                     RXU_BIT_THREE   =   4'h3,
                     RXU_BIT_FOUR    =   4'h4,
                     RXU_BIT_FIVE    =   4'h5,
                     RXU_BIT_SIX     =   4'h6,
                     RXU_BIT_SEVEN     =   4'h7,
                     RXU_PARITY      =   4'h8,
                     RXU_STOP        =   4'h9,
                     RXU_SECOND_STOP =   4'ha,
                     //RXU_BIT_X       =   4'hb,
                     //RXU_BIT_X       =   4'hc,
                     RXU_BREAK       =   4'hd,
                     RXU_RESET_IDLE  =   4'he,
                     RXU_IDLE        =   4'hf
)(
    input wire i_clk,
    input wire i_reset,
    input wire i_uart_rx,
    input wire [30:0] i_setup,
    output reg o_wr,
    output reg o_break,
    output reg o_parity_err, o_frame_err,
    output wire o_ck_uart,
    output reg[7:0] o_data
);

// Signals
wire [23:0] clocks_per_baud, half_baud;
wire [1:0] data_bits;
wire use_parity, parity_even, dblstop, fixd_parity;

// Registers
reg	[7:0] data_reg;
reg [29:0] r_setup;
reg [23:0] baud_counter;
reg [3:0] state;
reg calc_parity;
reg q_uart, qq_uart, ck_uart;
reg zero_baud_counter;
reg half_baud_time;
reg line_synch;
reg pre_wr;
reg [27:0] chg_counter; 
wire[27:0] break_condition; // vivado doesnt like it

// Assignments from the setup wire
assign data_bits       = r_setup[29:28];
assign dblstop        = r_setup[27];
assign use_parity      = r_setup[26];
assign fixd_parity     = r_setup[25];
assign parity_even     = r_setup[24];
assign clocks_per_baud = r_setup[23:0];

assign break_condition = { r_setup[23:0], 4'h0 };
assign half_baud       = {1'h0, r_setup[23:1]} - 24'h1; // divide by 2 and -1

// Async rx, therefore this is to avoid metastability by register input couple of clks over
initial q_uart  = 1'b0;
initial qq_uart = 1'b0;
initial ck_uart = 1'b0;

always @(posedge i_clk) 
    if(i_reset) 
        { ck_uart, qq_uart, q_uart } <= 3'h0;
    else 
        { ck_uart, qq_uart, q_uart } <= { qq_uart, q_uart, i_uart_rx }; // here it is stalling intentionally

     
assign	o_ck_uart = ck_uart;

// Break or idle?
initial	chg_counter = 0;
always @(posedge i_clk)
    if (i_reset)
        chg_counter <= 0;
    else if (qq_uart != ck_uart)
        chg_counter <= 0;
    else if (chg_counter < break_condition)
        chg_counter <= chg_counter + 1;

// Break
initial o_break = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        o_break <= 1'b0;
    else 
        o_break <= ((chg_counter >= break_condition) && (~ck_uart))? 1'b1: 1'b0;

// In between charactersq? line held for more clocks that would be in a charac
initial line_synch = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        line_synch <= 1'b0;
    else
        line_synch <= ((chg_counter >= break_condition)&&(ck_uart)); // high more than break_condition and 1

// Are we in a baud interval? in the middle of a start bit/
initial half_baud_time = 0;
always @(posedge i_clk)
    if (i_reset)
        half_baud_time <= 1'b0;
    else
        half_baud_time <= (~ck_uart)&&(chg_counter >= {4'h0,half_baud});
        
// Setup whenever
initial r_setup = INITIAL_SETUP[29:0];
always @(posedge i_clk)
    if (i_reset)
        r_setup <= INITIAL_SETUP[29:0];
    else if (state >= RXU_RESET_IDLE)
        r_setup <=i_setup[29:0];
    
//--------------------------------------------------------------------------------
// FSM logic
// RESET -> RESET_IDLE -> (when line is idle) -> IDLE
//	IDLE -> bit 0 -> bit 1 -> bit_{ndatabits} -> 
//		(optional) PARITY -> STOP -> (optional) SECOND_STOP
//		-> IDLE
//	ANY -> (on break) BREAK -> IDLE
initial	state = RXU_RESET_IDLE;
always @(posedge i_clk)
    // s:rst 
    if (i_reset)
        state <= RXU_RESET_IDLE;
        
    // s:rst_idle  
    else if (state == RXU_RESET_IDLE) begin
        // {{{
        if (line_synch)
             state <= RXU_IDLE; // Goto idle state from a reset
        else // Otherwise, stay in this condition 'til reset
            state <= RXU_RESET_IDLE;
        // }}}
        
    // s:o_break     
    end else if (o_break) begin // We are in a break condition
        state <= RXU_BREAK;
        
    // s:rxu_break    
    end else if (state == RXU_BREAK) begin // Goto idle state following return ck_uart going high
        // {{{
        if (ck_uart)
            state <= RXU_IDLE;
        else
            state <= RXU_BREAK;
        // }}}
    
    // s:rxu_idle    
    end else if (state == RXU_IDLE) begin // Idle state, independent of baud counter
        // {{{
        if (!ck_uart && half_baud_time) begin // We are in the center of a valid start bit
            case (data_bits)
            2'b00: state <= RXU_BIT_ZERO;
            2'b01: state <= RXU_BIT_ONE;
            2'b10: state <= RXU_BIT_TWO;
            2'b11: state <= RXU_BIT_THREE;
            endcase
        end else // Otherwise, just stay here in idle
            state <= RXU_IDLE;
        // }}}
    
    // s:zero_baud_counter    
    end else if (zero_baud_counter) begin
        // {{{
        if (state < RXU_BIT_SEVEN)
            // Data arrives LSB first. By the time this is clocked in, it's what you'll have.
            state <= state + 1;
        else if (state == RXU_BIT_SEVEN)
            state <= (use_parity) ? RXU_PARITY:RXU_STOP;
        else if (state == RXU_PARITY)
            state <= RXU_STOP;
        else if (state == RXU_STOP) begin // Stop (or parity) bit(s)
            if (!ck_uart) // On frame error, wait 4 ch idle
                state <= RXU_RESET_IDLE;
            else if (dblstop)
                state <= RXU_SECOND_STOP;
            else
                state <= RXU_IDLE;
        end else begin// state must equal RX_SECOND_STOP (this is to wait in case there is 2nd stop)
            if (!ck_uart) // On frame error, wait 4 ch idle
                state <= RXU_RESET_IDLE;
            else
                state <= RXU_IDLE;
        end
        // }}}
    //    
    end
    
// Data capture (dont care) until the end, and when the end comes if we have parity, keep it without updating
always @(posedge i_clk)
if ((zero_baud_counter)&&(state != RXU_PARITY)) 
    data_reg <= { ck_uart, data_reg[7:1]};   
    
// Calculation based on XOR of all prioir bits, on idle rst
always @(posedge i_clk)
if (i_reset)
    calc_parity <= 0;
else if (state == RXU_IDLE)
    calc_parity <= 0;
else if (zero_baud_counter)
    calc_parity <= calc_parity ^ ck_uart;
        
// Parity correction
initial o_parity_err = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        o_parity_err <= 1'b0;
    else if ((zero_baud_counter)&&(state == RXU_PARITY)) begin
        if (fixd_parity)   
            o_parity_err <= (ck_uart ^ parity_even);
        else if (parity_even)
            o_parity_err <= (calc_parity != ck_uart);
        else
            o_parity_err <= (calc_parity == ck_uart);
    end else if (state >= RXU_BREAK)
        o_parity_err <= 1'b0;
        
// Frame error = stop bits not high midway through the stop baud interval
initial o_frame_err = 1'b0;
always @(posedge i_clk)
if (i_reset)
    o_frame_err <= 1'b0;
else if ((zero_baud_counter)&&(state == RXU_STOP) || (state == RXU_SECOND_STOP))
    o_frame_err <= (o_frame_err)||(~ck_uart);
        
// data bit logic and flag, pre_wr is there cause frame correction stopbit2 will not be known 
initial o_data = 8'h00;
initial pre_wr = 1'b0;
always @(posedge i_clk)
    if (i_reset) begin
        pre_wr <= 1'b0;
        o_data <= 8'h00;
    end else if ((zero_baud_counter)&&(state == RXU_STOP)) begin
    	pre_wr <= 1'b1;
            case (data_bits)
            2'b00: o_data <= data_reg;
            2'b01: o_data <= { 1'b0, data_reg[7:1] };
            2'b10: o_data <= { 2'b0, data_reg[7:2] };
            2'b11: o_data <= { 3'b0, data_reg[7:3] };
            endcase
    end else if ((zero_baud_counter)||(state == RXU_IDLE))
        pre_wr <= 1'b0;
 
// o_wr the actual flag when we ready
initial o_wr = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        o_wr <= 1'b0;
    else if ((zero_baud_counter)||(state == RXU_IDLE))
        o_wr <= (pre_wr)&&(!i_reset);
    else
        o_wr <= 1'b0; 
        
always @(posedge i_clk)
    if (i_reset)
        baud_counter <= INITIAL_SETUP[23:0]-1;
    else if (zero_baud_counter)
        baud_counter <= clocks_per_baud - 1;
    else case(state)
        RXU_RESET_IDLE: baud_counter <=clocks_per_baud-1;
        RXU_BREAK     : baud_counter <=clocks_per_baud-1;
        RXU_IDLE      : baud_counter <=clocks_per_baud-1;
    endcase
    
// precharfe (baud_counter==0?) test on the clock before cleaning up time dependencies
initial zero_baud_counter = 1'b0;
always @(posedge i_clk)
if (state == RXU_IDLE)
    zero_baud_counter <= 1'b0;
else
    zero_baud_counter <= (baud_counter ==1);
    

endmodule


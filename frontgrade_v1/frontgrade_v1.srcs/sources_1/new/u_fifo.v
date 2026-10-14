`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Radtest Ltd.
// Engineer: Mariana MM
// 
// Create Date: 10/09/2026 07:48:51 PM
// Design Name: 
// Module Name: u_fifo
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

`default_nettype	none // so that if it is not defined we catch it
module u_fifo #(
        parameter BW = 8,
        parameter [3:0] LGFLEN = 4,
        parameter [0:0] RXFIFO = 1'b1,
        localparam FLEN = (1<<LGFLEN) // shift binary value one to the left
    )(
        input wire i_clk, i_reset,
        input wire i_wr, i_rd,
        input wire [(BW-1):0] i_data,
        output wire o_empty_n,
        output wire [(BW-1):0] o_data,
        output wire [15:0] o_status,
        output wire o_err
    );


// Signal declaration
reg	[(BW-1):0]	fifo[0:(FLEN-1)]; // upsidedown?
reg	[(BW-1):0]	r_data, last_write;
reg	[(LGFLEN-1):0]	wr_addr, rd_addr, r_next;
reg	will_overflow, will_underflow;
reg	osrc;

wire [(LGFLEN-1):0]	w_waddr_plus_one, w_waddr_plus_two;
wire w_write, w_read;
reg	[(LGFLEN-1):0] r_fill;
wire [3:0] lglen;
wire w_half_full;
reg	[9:0]w_fill;

assign	w_waddr_plus_two = wr_addr + 2;
assign	w_waddr_plus_one = wr_addr + 1;

// Write half
// will_overflow
initial will_overflow = 1'b0;
always @(posedge i_clk)
    if (i_reset)
        will_overflow <= 1'b0;
    else if (i_rd)
        will_overflow <= (will_overflow)&&(i_wr);
	else if (w_write)
		will_overflow <= (will_overflow)||(w_waddr_plus_two == rd_addr);
	else if (w_waddr_plus_one == rd_addr)
		will_overflow <= 1'b1;
		
// wr_addr
initial	wr_addr = 0;
always @(posedge i_clk)
    if (i_reset)
        wr_addr <= { (LGFLEN){1'b0} }; // replicate the bit 0 LGFLEN times
    else if (w_write)
        wr_addr <= w_waddr_plus_one;

// writing to the fifo
always @(posedge i_clk)
    if(w_write)
        fifo[wr_addr] <= i_data;

//	Following a read, the next sample will be available on the
//	next clock
//	Clock	ReadCMD	ReadAddr	Output
//	0	0	0		fifo[0]
//	1	1	0		fifo[0]
//	2	0	1		fifo[1]
//	3	0	1		fifo[1]
//	4	1	1		fifo[1]
//	5	1	2		fifo[2]
//	6	0	3		fifo[3]
//	7	0	3		fifo[3]
// }}}

// will underflow
initial	will_underflow = 1'b1;
always @(posedge i_clk)
    if (i_reset)
        will_underflow <= 1'b1;
    else if (i_wr)
        will_underflow <= 1'b0;
    else if (w_read)
        will_underflow <= (will_underflow)||(r_next == wr_addr);
        
// overflow is reported, underflow isnt
initial	rd_addr = 0;
initial	r_next  = 1;
always @(posedge i_clk)
    if (i_reset) begin
        rd_addr <= 0;
        r_next  <= 1;
    end else if (w_read) begin
        rd_addr <= rd_addr + 1;
        r_next  <= rd_addr + 2;
    end

// read from the fifo
always @(posedge i_clk)
	if (w_read)
		r_data <= fifo[r_next[LGFLEN-1:0]];
	
// last write 
always @(posedge i_clk)
	if (i_wr && (!o_empty_n || (w_read && r_next == wr_addr)))
		last_write <= i_data;
		
// osrc		
initial	osrc = 1'b0;
always @(posedge i_clk)
	if (i_reset)
		osrc <= 1'b0;
	else if (i_wr && (!o_empty_n || (w_read && r_next == wr_addr)))
		osrc <= 1'b1;
	else if (i_rd)
		osrc <= 1'b0;
		
assign o_data = (osrc) ? last_write : r_data;

// r_fill receive fifo = counts the number of values yet to be read
//        transmit fifo = number of empty positions that can still be filled before full
generate if (RXFIFO)
begin : RXFIFO_FILL // number of element calculation
    initial r_fill = 0;
    always @(posedge i_clk)
        if (i_reset)
            r_fill <= 0;
       else case({ w_write, w_read})
            2'b01:	r_fill <= r_fill - 1'b1; // read -1
            2'b10:	r_fill <= r_fill + 1'b1; // write +1
           default: begin end
           endcase       
end else begin : TXFIFO_FILL // number of empty elements
    initial	r_fill = -1;
    always @(posedge i_clk)
		if (i_reset)
			r_fill <= -1;
		else case({ w_write, w_read })
            2'b01:	r_fill <= r_fill + 1'b1;
            2'b10:	r_fill <= r_fill - 1'b1;
            default:  begin end
            endcase
end endgenerate

// any other overflows
assign o_err = (i_wr && !w_write);
assign lglen = LGFLEN;

always @(*) // execute this program anytime the signal it reads changes
begin
    w_fill = 0;
    w_fill[(LGFLEN-1):0] = r_fill;
end

assign	w_half_full = r_fill[(LGFLEN-1)];

assign o_status ={
    lglen, //  4'bit nibble. 2^(this value).  4'h4 in this position means FIFO has 2^4 or 16 values within it.
    w_fill, // number Empty elements within the FIFO that can yet be filled.
    w_half_full, //  If 1, a halfway interrupt can be sent indicating a half  (either transmit or receive) will be successful.
    (RXFIFO!=0)?!will_underflow:!will_overflow // indicated it is possible 
};   

assign	o_empty_n = !will_underflow;

//--------------------------------------------------------------------------------------
// Formal verification 
`ifdef	FORMAL
	reg	f_past_valid;
	initial	f_past_valid = 0;
	//
	always @(posedge i_clk)
	   f_past_valid <= 1;  
	
	// Pointer Checks   
    reg	[LGFLEN-1:0]	f_fill;
	wire	[LGFLEN-1:0]	f_raddr_plus_one;
    //
	always @(*)
		f_fill = wr_addr - rd_addr;
    //
	always @(*)
		assert(will_underflow == (f_fill == 0));
    //
	always @(*)
		assert(will_overflow  == (&f_fill)); // AND check all bits
    //
	assign	f_raddr_plus_one = rd_addr + 1;
	always @(*)
		assert(f_raddr_plus_one  == r_next);
    //
	always @(*)
        if (will_underflow) begin
            assert(!w_read);
            assert(!osrc);
	end
    //
	always @(posedge i_clk)
        if (RXFIFO)
            assert(r_fill == f_fill);
        else
            assert(r_fill == (~f_fill));  
       
//--------------------------------------------------------------------------------------     
`ifdef	UFIFO // Declare two arbitrary addresses and data values !!!!
	(* anyconst *) reg [LGFLEN-1:0]	f_const_addr;
	(* anyconst *) reg [BW-1:0]	f_const_data, f_const_second;
	reg [LGFLEN-1:0]	f_next_addr;
	reg	[1:0] f_state;
	reg	f_first_in_fifo, f_second_in_fifo;
	reg	[LGFLEN-1:0] f_distance_to_first, f_distance_to_second;

	// Determine if those data values are at their addresses in the FIFO
	always @(*)
	begin
		f_next_addr = f_const_addr + 1;
		f_distance_to_first  = f_const_addr - rd_addr;
		f_distance_to_second = f_next_addr  - rd_addr;
		//
		f_first_in_fifo  = (f_distance_to_first  < f_fill)
			&& !will_underflow
			&& (fifo[f_const_addr] == f_const_data);
		f_second_in_fifo = (f_distance_to_second < f_fill)
			&& !will_underflow
			&& (fifo[f_next_addr] == f_const_second);
	end

	// Generate the twin-write state machine
	initial	f_state = 2'b00;
	always @(posedge i_clk)
	if (i_reset)
		f_state <= 2'b00;
        else case(f_state)
        2'b00: if (w_write && (wr_addr == f_const_addr) && (i_data == f_const_data))
            f_state <= 2'b01;
        2'b01: if (w_read && (rd_addr == f_const_addr))
                    f_state <= 2'b00;
               else if (w_write && (wr_addr == f_next_addr))
                    f_state <= (i_data == f_const_second) ? 2'b10 : 2'b00;
        2'b10: if (w_read && (rd_addr == f_const_addr))
                f_state <= 2'b11;
        2'b11: if (w_read)
                f_state <= 2'b00;
        endcase
        
	// Check conditions against the twin write state machine
	always @(*)
	case(f_state)
	2'b00: begin end
	2'b01: begin
		assert(!will_underflow);
		assert(f_first_in_fifo);
		assert(!f_second_in_fifo); // uno no el otro
		assert(wr_addr == f_next_addr);
		assert(fifo[f_const_addr] == f_const_data);
		if (rd_addr == f_const_addr)
			assert(o_data == f_const_data);
		end
	2'b10: begin
		assert(f_first_in_fifo);
		assert(f_second_in_fifo);
		end
	2'b11: begin
		assert(f_second_in_fifo);
		assert(rd_addr == f_next_addr);
		assert(o_data  == f_const_second);
		end
	endcase
`endif


    // Cover checks
    reg	cvr_filled;
    always @(*)
        cover(o_empty_n);

// Can't cover the FIFO being full when the FIFO is a member of another components--so we only check that we can be filled here
`ifdef	UFIFO
	always @(*)
		cover(o_err);
    //
	initial	cvr_filled = 0;
	always @(posedge i_clk)
        if (i_reset)
            cvr_filled <= 0;
        else if (&f_fill[LGFLEN-1:0])
            cvr_filled <= 1;
	always @(*)
		cover(cvr_filled && !o_empty_n);
`endif // UFIFO
	// }}}
`endif // FORMAL

endmodule
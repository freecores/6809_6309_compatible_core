/*
 * Synthesis top Module for the MC6809/HD6309 compatible core.
 * This top module has been tested in the MachXO2-7000HE breakout board
 * (c) 2013 R.A. Paz Schmidt rapazschmidt@gmail.com
 * Distributed under the terms of the Lesser GPL
 *
 * Implemented using diamond 2.1
 */
 
module CC3_top(
	input wire clk40_i,
	/* CPU Bus */
	output wire cpuclk_o,
	output wire reset_o,
	output wire [15:0] addr_o,
	output wire oen_o,
	output wire wen_o,
	output wire cen_o,
	output wire [7:0] data_io,
	output wire [5:0] state_o,
	/* Debug */
	output wire [7:0] leds_o,
	/* VGA output */
	output wire hsync_o,
	output wire vsync_o,
	output wire red_o,
	output wire green_o,
	output wire blue_o
	
	);
reg cpu_clk, clk_div2;
reg [3:0] reset_cnt;
reg [7:0] leds_r;

/* CPU IO */
wire [15:0] cpu0_addr_o, cpu1_addr_o;
wire [7:0] cpu0_data_in, cpu0_data_out, cpu1_data_in, cpu1_data_out;
wire cpu0_we, cpu0_oe, cpu1_we, cpu1_oe, cpu_reset;
wire [5:0] cpu0_state;
/* Module io */

assign addr_o = cpu0_addr_o;
assign data_io = cpu0_we ? cpu0_data_out:cpu0_data_in;
/*
assign hsync_o = 0;
assign vsync_o = 0;
assign red_o = 0;
assign green_o = 0;
assign blue_o = 0;
*/
assign leds_o = leds_r;

assign oen_o = !cpu0_oe;
assign wen_o = cpu0_we & (cpu0_addr_o[15:12] == 4'h0);
assign cen_o = !(cpu0_oe | cpu0_we);
assign cpuclk_o = cpu_clk;
assign reset_o = cpu_reset;
assign state_o = cpu0_state;

always @(posedge clk40_i)
	cpu_clk <= !cpu_clk;

assign cpu_reset = reset_cnt != 4'd14;
always @(posedge cpu_clk)
	begin
		if (reset_cnt != 4'd14)
			reset_cnt <= reset_cnt + 4'h1;
		if (cpu0_we)
			leds_r <= cpu0_data_out;
	end
	

MC6809_cpu cpu0(
	.cpu_clk(cpu_clk),
	.cpu_reset(cpu_reset),
	.cpu_nmi_n(1'b0),
	.cpu_irq_n(1'b0),
	.cpu_firq_n(1'b0),
	.cpu_state_o(cpu0_state),
	.cpu_we_o(cpu0_we),
	.cpu_oe_o(cpu0_oe),
	.cpu_addr_o(cpu0_addr_o),
	.cpu_data_i(cpu0_data_in),
	.cpu_data_o(cpu0_data_out)
	);
	
/* Memory */

wire bios_en, video_en;
wire [7:0] data_from_bios, data_from_video;

assign bios_en = cpu0_addr_o[15:12] == 4'hf;
assign video_en = cpu0_addr_o[15:12] == 4'h0;

assign cpu0_data_in = bios_en ? data_from_bios:
                     video_en ? data_from_video:8'hzz;

bios2k bios(
	.DataInA(cpu0_data_out[7:0]), 
	.DataInB(cpu1_data_out[7:0]), 
	.AddressA(cpu0_addr_o[10:0]), 
	.AddressB(cpu1_addr_o[10:0]), 
	.ClockA(clk40_i), 
	.ClockB(clk40_i), 
    .ClockEnA((cpu0_oe | cpu_we) & bios_en),
	.ClockEnB(1'b0), 
	.WrA(cpu0_we & bios_en), 
	.WrB(1'b0),//cpu1_we), 
	.ResetA(1'b0), 
	.ResetB(1'b0), 
	.QA(data_from_bios), 
	.QB()
	);


vgatext textctrl(
	.CLK(clk40_i),
	.RESET(cpu_reset),
	.HSYNC(hsync_o),
	.VSYNC(vsync_o),
	.RED(red_o),
	.GREEN(green_o),
	.BLUE(blue_o),
	.CPU_CLK(clk40_i),
	.CPU_ADDR(cpu0_addr_o[11:0]),
	.CPU_OE_EN(cpu0_oe & video_en),
	.CPU_WR_EN(cpu0_we & video_en),
	.CPU_DATA_O(cpu0_data_out),
	.CPU_DATA_I(data_from_video)
	);



endmodule

/* 
 *
 * MC6809/HD6309 Compatible code
 * (c) 2013 R.A. Paz Schmidt
 * distributed under the terms of the Lesser GPL, see LICENSE.TXT
 *
 */

`include "defs.v"
module MC6809_cpu(
	input  wire cpu_clk,
	input  wire cpu_reset,
	input  wire cpu_nmi_n,
	input  wire cpu_irq_n,
	input  wire cpu_firq_n,
	output wire [5:0] cpu_state_o,
	output wire cpu_we_o,
	output wire cpu_oe_o,
	output wire [15:0] cpu_addr_o,
	input  wire [7:0] cpu_data_i,
	output wire [7:0] cpu_data_o,
	input wire debug_clk,
	output wire debug_data_o // serial debug info, 64 bit shift register
	
	);

wire k_reset;

reg [7:0] k_opcode, k_postbyte, k_ind_ea; /* all bytes of an instruction */
reg [7:0] k_pp_regs; // push/pull registers to process
reg [3:0] k_pp_active_reg; // push/pull active register 
reg [7:0] k_memhi, k_memlo, k_cpu_data_o; /* operand read from memory */
reg [7:0] k_ofslo, k_ofshi, k_eahi, k_ealo;
reg [5:0] state, // state of the main state machine
          next_state, // next state to exit to from the read from [PC] state machine
		  next_mem_state, // next state to exit to from the read from memory state machine
		  next_push_state; // next state to exit to from push multiple state machine
reg k_write_tfr, k_write_exg;
reg k_cpu_oe, k_cpu_we, k_inc_pc;
reg k_indirect_loaded; // set when in indirect indexed and the address has been loaded
reg [15:0] k_cpu_addr, k_new_pc;
reg k_write_pc, k_inc_su, k_dec_su, k_set_e, k_clear_e;
reg [1:0] k_mem_dest;
reg k_mul_cnt; // multiplier couner
reg k_write_dest; // set for 1 clock when a register has to be written, dec_o_dest_reg_addr has the register source
reg k_write_post_incdec; // asserted when in the last write cycle or in write back for loads
reg k_forced_mem_size; // used to force the size of a memory read to be 16 bits, used for vector fetch
/****
 * Decoder outputs 
 */
wire [2:0] dec_o_p1_mode; // addressing mode
wire [2:0] dec_o_p1_optype; // k_opcode type
wire dec_o_use_s; // signals when S should be used instead of U
wire dec_o_alu_size; /* size of the result of an alu opcode (destination to be written) */
/* ea decoder */
wire dec_o_ea_ofs8, dec_o_ea_ofs16, dec_o_ea_wpost, dec_o_ea_ofs0, dec_o_ea_indirect;
/* alu k_opcode decoder */
wire [4:0] dec_o_alu_opcode;
wire [1:0] dec_o_right_path_mod; /* Modifier for alu's right path input */
/* register decoder */
wire dec_o_wdest, dec_o_source_size, dec_o_write_flags;
wire [3:0] dec_o_left_path_addr, dec_o_right_path_addr, dec_o_dest_reg_addr;
// latched versions, used for muxes, regs and alu
wire [3:0] dec_lo_left_path_addr, dec_lo_right_path_addr, dec_lo_dest_reg_addr;
/* test condition */
wire dec_o_cond_taken;
/* ALU outputs */
wire [15:0] alu_o_result;
wire [7:0] alu_o_CCR;
wire [7:0] alu8_o_result;
wire [7:0] alu8_o_CCR;
/* Register Module outputs */
wire [15:0] regs_o_left_path_data, regs_o_right_path_data, regs_o_eamem_addr, regs_o_su;
wire [7:0] regs_o_dp;
wire [15:0] regs_o_pc;
wire [7:0] regs_o_CCR;
/* Data Muxes */
reg [3:0] datamux_o_dest_reg_addr, datamux_o_alu_in_left_path_addr;
reg [15:0] datamux_o_alu_in_left_path_data, datamux_o_alu_in_right_path_data, datamux_o_dest;

reg k_p2_valid, k_p3_valid; /* 1 when k_postbyte has been loaded for page 2 or page 3 */

/* * Interrupt sync registers 
 */

reg [2:0] k_reg_nmi, k_reg_irq, k_reg_firq;
wire k_nmi_req, k_firq_req, k_irq_req;

assign k_nmi_req = k_reg_nmi[2] & k_reg_nmi[1];
assign k_firq_req = k_reg_firq[2] & k_reg_firq[1];
assign k_irq_req = k_reg_irq[2] & k_reg_irq[1];

/* Debug */
`ifdef SERIAL_DEBUG
reg [63:0] debug_r;

always @(posedge debug_clk)
	begin
		if (cpu_clk)
			begin
				debug_r[15:0] <= regs_o_pc;
				debug_r[23:16] <= k_opcode;
				debug_r[27:24] <= datamux_o_alu_in_left_path_addr;
				debug_r[31:28] <= dec_o_right_path_addr;
				debug_r[35:32] <= datamux_o_dest_reg_addr;
				debug_r[39:36] <= { k_write_pc, 1'b0, k_mem_dest}; //regs_o_CCR[3:0];
				debug_r[55:40] <= { k_memhi,k_memlo };//k_new_pc;
				debug_r[63:56] <= cpu_data_i;
			end
		else
			debug_r <= debug_r << 1; // shift out
	end

assign debug_data_o = debug_r[63];
`else
assign debug_data_o = 1'b0;
`endif
alu alu(
	.clk_in(cpu_clk),
	.a_in(datamux_o_alu_in_left_path_data),
	.b_in(datamux_o_alu_in_right_path_data),
	.CCR(regs_o_CCR), /* flags */
	.opcode_in(dec_o_alu_opcode), /* ALU k_opcode */
	.sz_in(dec_o_alu_size),
	.q_out(alu_o_result), /* ALU result */
	.CCRo(alu_o_CCR)
	);


regblock regs(
	.clk_in(cpu_clk),
	.path_left_addr(datamux_o_alu_in_left_path_addr),
	.path_right_addr(dec_lo_right_path_addr),
	.write_reg_addr(datamux_o_dest_reg_addr),
	.exg_dest_r(k_postbyte[7:4]),
	.eapostbyte( k_ind_ea ),
	.offset16({ k_ofshi, k_ofslo }),
	.write_reg(k_write_dest),
	.write_tfr(k_write_tfr),
	.write_exg(k_write_exg),
	.write_post(k_write_post_incdec),
	.write_pc(k_write_pc),
	.inc_pc(k_inc_pc),
	.inc_su(k_inc_su),
	.dec_su(k_dec_su),
	.use_s(dec_o_use_s),
	.data_w(datamux_o_dest),
	.new_pc(k_new_pc),
	.CCR_in(alu_o_CCR), 
	.write_flags(dec_o_write_flags & (state == `SEQ_GRAL_WBACK)),
	.set_e(k_set_e),
	.clear_e(k_clear_e),
	.CCR_o(regs_o_CCR), 
	.path_left_data(regs_o_left_path_data),
	.path_right_data(regs_o_right_path_data),
	.eamem_addr_o(regs_o_eamem_addr),
	.reg_pc(regs_o_pc),
	.reg_dp(regs_o_dp),
	.reg_su(regs_o_su)
);

decode_regs dec_regs(
	.cpu_clk(cpu_clk),
	.opcode(k_opcode),
	.postbyte0(k_postbyte),
	.page2_valid(k_p2_valid),
	.page3_valid(k_p3_valid),
	.path_left_addr_o(dec_o_left_path_addr),
	.path_right_addr_o(dec_o_right_path_addr),
	.dest_reg_o(dec_o_dest_reg_addr),
	.path_left_addr_lo(dec_lo_left_path_addr),
	.path_right_addr_lo(dec_lo_right_path_addr),
	.dest_reg_lo(dec_lo_dest_reg_addr),
	.write_dest(dec_o_wdest),
	.source_size(dec_o_source_size),
	.result_size(dec_o_alu_size)
	);

decode_op dec_op(
	.opcode(k_opcode),
	.postbyte0(k_postbyte),
	.page2_valid(k_p2_valid),
	.page3_valid(k_p3_valid),
	.mode(dec_o_p1_mode),
	.optype(dec_o_p1_optype),
	.use_s(dec_o_use_s)
	);
	
decode_ea dec_ea(
	.eapostbyte( k_ind_ea ),
	.noofs(dec_o_ea_ofs0),
	.ofs8(dec_o_ea_ofs8),
	.ofs16(dec_o_ea_ofs16),
	.write_post(dec_o_ea_wpost),
	.isind(dec_o_ea_indirect)
	);

/* Opcodes for the ALU are decoded here
 * Write Flags are also decoded here 
 */
decode_alu dec_alu(
	.opcode(k_opcode),
	.postbyte0(k_postbyte),
	.page2_valid(k_p2_valid),
	.page3_valid(k_p3_valid),
	.alu_opcode(dec_o_alu_opcode),
	.dec_alu_right_path_mod(dec_o_right_path_mod),
	.dest_flags(dec_o_write_flags)
	);
/* Condition decoder */
test_condition test_cond(
	.opcode(k_opcode),
	.postbyte0(k_postbyte),
	.page2_valid(k_p2_valid),
	.CCR(regs_o_CCR),
	.cond_taken(dec_o_cond_taken)
	);

/* Module IO */
	
assign cpu_oe_o = k_cpu_oe; // we latch on the rising edge
assign cpu_we_o = k_cpu_we;
assign cpu_addr_o = k_cpu_addr;
assign cpu_data_o = k_cpu_data_o;
assign k_reset = cpu_reset;
assign cpu_state_o = state;
		

/* Left Register read mux
 */
always @(*)
	begin
		if (k_pp_active_reg != `RN_INV)
			datamux_o_alu_in_left_path_addr = k_pp_active_reg;
		else
			datamux_o_alu_in_left_path_addr = dec_lo_left_path_addr;
	end

/* Destination register address MUX
 */
always @(*)
	begin
		if (k_pp_active_reg != `RN_INV)
			datamux_o_dest_reg_addr = k_pp_active_reg;
		else
			datamux_o_dest_reg_addr = dec_lo_dest_reg_addr;
	end

/* Destination register data mux
 * selects the source to write to register. 16 bit registers have to be written at once after reading the low byte
 *
 */
always @(*)
	begin
		datamux_o_dest = alu_o_result;
		case (dec_o_p1_optype)
			`OP_PULL, `OP_RTS: // destination register
				datamux_o_dest = { k_memhi, k_memlo };
			`OP_LEA:
				if (dec_o_ea_indirect)// & dec_o_alu_size)
					datamux_o_dest = { k_memhi, k_memlo };
				else
					datamux_o_dest = regs_o_eamem_addr;
		endcase
	end

/* ALU left input mux */

always @(*)
	begin
		if (dec_lo_left_path_addr == `RN_MEM8)
			datamux_o_alu_in_left_path_data = { k_memhi, k_memlo };
		else
		case (dec_o_p1_optype)
			`OP_LEA:
				if (dec_o_ea_indirect)// & dec_o_alu_size)
					datamux_o_alu_in_left_path_data = { k_memhi, k_memlo };
				else
					datamux_o_alu_in_left_path_data = regs_o_eamem_addr;
			default:
				datamux_o_alu_in_left_path_data = regs_o_left_path_data;
		endcase
	end
/* PC as destination from jmp/bsr mux */
always @(*)
	begin
		k_new_pc = { k_memhi,k_memlo }; // used to fetch reset vector
		if (k_mem_dest != `MEMDEST_PC)
			begin
				case (dec_o_p1_mode)
					`REL16: k_new_pc = regs_o_pc + { k_memhi,k_memlo };
					`REL8: k_new_pc = regs_o_pc + { {8{k_memlo[7]}}, k_memlo };
					`EXTENDED: k_new_pc = { k_eahi,k_ealo };
					`DIRECT: k_new_pc = { regs_o_dp, k_ealo };
					`INDEXED:
						if (dec_o_ea_indirect)
							k_new_pc = { k_memhi,k_memlo };
						else
							k_new_pc = regs_o_eamem_addr;
				endcase
			end
	end
/* ALU right input mux */
always @(*)
	begin
		case (dec_lo_right_path_addr)
			`RN_MEM8:
				datamux_o_alu_in_right_path_data = { 8'h00, k_memlo };
			`RN_MEM16:
				datamux_o_alu_in_right_path_data = { k_memhi, k_memlo };
			`RN_IMM8:
				datamux_o_alu_in_right_path_data = { 8'h0, k_memlo };
			`RN_IMM16:
				datamux_o_alu_in_right_path_data = { k_memhi, k_memlo };
			default:
				case (dec_o_right_path_mod)
					`MOD_DEFAULT: datamux_o_alu_in_right_path_data = regs_o_right_path_data;
					`MOD_ONE: datamux_o_alu_in_right_path_data = 16'h0001;
					`MOD_ZERO: datamux_o_alu_in_right_path_data = 16'h0000;
					`MOD_MINUS1: datamux_o_alu_in_right_path_data = 16'hffff;
				endcase	
		endcase
	end

always @(posedge cpu_clk or posedge k_reset)
	begin
		if (k_reset == 1'b1)
			begin
				state <= `SEQ_COLDRESET;
				k_reg_nmi <= 0;
				k_reg_firq <= 0;
				k_reg_irq <= 0;
			end
		else
			begin
				/* Inrerrupt recognition and acknowledge */
				if (!k_reg_nmi[2])
					k_reg_nmi <= { k_reg_nmi[1:0], cpu_nmi_n };
				if (!k_reg_irq[2])
					k_reg_irq <= { k_reg_irq[1:0], cpu_irq_n };
				if (!k_reg_firq[2])
					k_reg_firq <= { k_reg_firq[1:0], cpu_firq_n };
				/* modifier registers */
				if (k_inc_pc)
					k_inc_pc <= 0;
				if (k_write_pc)
					k_write_pc <= 0;
				if (k_cpu_we)
					k_cpu_we <= 0;					
				if (k_cpu_oe)
					k_cpu_oe <= 0;
				if (k_write_post_incdec)
					k_write_post_incdec <= 0;
				if (k_dec_su)
					k_dec_su <= 0;
				if (k_inc_su)
					k_inc_su <= 0;
				if (k_set_e)
					k_set_e <= 0;
				if (k_clear_e)
					k_clear_e <= 0;
				if (k_write_dest)
					k_write_dest <= 0;
				if (k_write_exg)
					k_write_exg <= 0;
				if (k_write_tfr)
					k_write_tfr <= 0;
			case (state)
				`SEQ_COLDRESET: 
					begin
						k_forced_mem_size <= 1;
						state <= `SEQ_MEM_READ_H;
						k_eahi <= 8'hff;
						k_ealo <= 8'hfe;
						next_mem_state <= `SEQ_LOADPC;
						k_mem_dest <= `MEMDEST_PC;
					end
				`SEQ_NMI:
					begin
						k_forced_mem_size <= 1;
						k_reg_nmi <= 3'h0;
						{ k_eahi, k_ealo } <= 16'hfffc;
						k_pp_regs <= 8'hff;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_SWI:
					begin
						k_forced_mem_size <= 1;
						state <= `SEQ_MEM_READ_H;
						{ k_eahi, k_ealo } <= 16'hfffa;
						k_pp_regs <= 8'hff;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
						k_set_e <= 1;
					end
				`SEQ_IRQ:
					begin
						k_forced_mem_size <= 1;
						k_reg_irq <= 3'h0;
						state <= `SEQ_MEM_READ_H;
						{ k_eahi, k_ealo } <= 16'hfff8;
						k_pp_regs <= 8'hff;
						next_mem_state <= `SEQ_PREPUSH;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_FIRQ:
					begin
						k_forced_mem_size <= 1;
						k_reg_firq <= 3'h0;
						{ k_eahi, k_ealo } <= 16'hfff6;
						k_pp_regs <= 8'h81; // PC & CC
						k_clear_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_SWI2:
					begin
						k_forced_mem_size <= 1;
						{ k_eahi, k_ealo } <= 16'hfff4;
						k_pp_regs <= 8'hff;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_SWI3:
					begin
						k_forced_mem_size <= 1;
						{ k_eahi, k_ealo } <= 16'hfff2;
						k_pp_regs <= 8'hff;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_UNDEF:
					begin
						k_forced_mem_size <= 1;
						{ k_eahi, k_ealo } <= 16'hfff0;
						k_pp_regs <= 8'hff;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_MEM_READ_H; // than load new PC
						next_mem_state <= `SEQ_FETCH; // than continue fetching instructions
					end
				`SEQ_LOADPC: /* loads the PC with the address taken from the reset vector */
					begin
						$display("cpu_data_i %02x %t", cpu_data_i, $time);
						state <= `SEQ_FETCH;
						k_mem_dest <= `MEMDEST_MH; // operand to memlo/memhi
					end
				`SEQ_FETCH: /* execution starts here */
					begin
						if (k_nmi_req)
							state <= `SEQ_NMI;
						else
						if (k_firq_req & `FLAGF)
							state <= `SEQ_FIRQ;
						else
						if (k_irq_req & `FLAGI)
							state <= `SEQ_IRQ;
						else
							begin
								state <= `SEQ_FETCH_1;
								k_cpu_addr <= regs_o_pc;
							end
					end
				`SEQ_FETCH_1:
					begin
						k_cpu_oe <= 1;
						k_inc_pc <= 1;
						k_p2_valid <= 0; // set when an k_opcode is page 2
						k_p3_valid <= 0; // set when an k_opcode is page 3
						k_pp_active_reg <= `RN_INV; // ensures that only push/pull control the left/dest muxes
						state <= `SEQ_FETCH_2;
					end
				`SEQ_FETCH_2:
					begin
						k_opcode <= cpu_data_i;
						case (cpu_data_i[7:0]) /* page 2 & 3 opcodes are recognized here */
							8'h10: 
								begin
									k_p2_valid <= 1;
									state <= `SEQ_FETCH_3;
								end
							8'h11:
								begin
									k_p3_valid <= 1;
									state <= `SEQ_FETCH_3;
								end
							8'h1e, 8'h1f:
								state <= `SEQ_FETCH_3; // tfr, exg, treated separately
							default:
								state <= `SEQ_DECODE;
						endcase
					end
				`SEQ_FETCH_3:
					begin
						state <= `SEQ_FETCH_4;
						k_cpu_addr <= regs_o_pc;
					end
				`SEQ_FETCH_4:
					begin
						k_cpu_oe <= 1;
						state <= `SEQ_FETCH_5;
					end
				`SEQ_FETCH_5: /* fetches a page 2 or 3 opcode */
					begin
						k_postbyte <= cpu_data_i;
						k_inc_pc <= 1;
						state <= `SEQ_DECODE_P23;
					end
				`SEQ_DECODE:
					begin
						/* here we have the first byte of the opcode and should be decided to which state we jump
						 * inherent means that no extra info is needed
						 * ALU opcodes need routing of registers to/from the ALU to the registers
						 */
						case (dec_o_p1_mode)
							`NONE: // unknown opcode or push/pull... refetch ?
								begin
									casex (k_opcode)
										8'h13: state <= `SEQ_SYNC;
										8'h39: // RTS
											begin
												state <= `SEQ_PREPULL;
												k_pp_regs <= 8'h80; // Pull PC (RTS)all regs
											end
										8'b001101x0: // PUSH S&U
											begin
												state <= `SEQ_PC_READ_L;
												next_state <= `SEQ_PREPUSH;
												next_push_state <= `SEQ_FETCH;
											end
										8'b001101x1: // PULL S&U
											begin
												next_state <= `SEQ_PREPULL;
												state <= `SEQ_PC_READ_L;
											end
										8'h3B: // RTI
											begin
												state <= `SEQ_PREPULL;
												k_pp_regs <= 8'hff; // all regs
											end
										default: /* we ignore unknown opcodes */
											state <= `SEQ_FETCH;
									endcase
								end
							`IMMEDIATE:	// 8 or 16 bits as result decides..
								begin
									if (dec_o_alu_size)
										state <= `SEQ_PC_READ_H;
									else
										state <= `SEQ_PC_READ_L;
									next_state <= `SEQ_GRAL_ALU;
								end
							`INHERENT:
								begin
									case (k_opcode)
										8'h3d: begin k_mul_cnt <= 1'h1; state <= `SEQ_GRAL_ALU; end // counter for mul
										8'h3f: state <= `SEQ_SWI;
											default: state <= `SEQ_GRAL_ALU;
									endcase
								end
							`DIRECT:
								begin
									state <= `SEQ_PC_READ_L; // loads address
									case (dec_o_p1_optype)
										`OP_JSR: next_state <= `SEQ_JSR_PUSH;
										`OP_JMP: next_state <= `SEQ_JMP_LOAD_PC;
										default:
											begin
												k_mem_dest <= `MEMDEST_MH; // operand to memlo/memhi
												if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
													(dec_o_left_path_addr == `RN_MEM8))
													begin
														next_state <= `SEQ_MEM_READ_H;
														next_mem_state <= `SEQ_GRAL_ALU; // read then alu
													end
												else
													next_state <= `SEQ_GRAL_ALU; // no read
												k_eahi <= regs_o_dp;
											end
									endcase
								end
							`INDEXED:
								state <= `SEQ_IND_READ_EA;
							`EXTENDED:
								begin
									state <= `SEQ_PC_READ_H; // loads address
									case (dec_o_p1_optype)
										`OP_JSR: next_state <= `SEQ_JSR_PUSH;
										`OP_JMP: next_state <= `SEQ_JMP_LOAD_PC;
										default:
											begin
												k_mem_dest <= `MEMDEST_MH; // operand to memlo/memhi
												if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
													(dec_o_left_path_addr == `RN_MEM8))
													begin
														next_state <= `SEQ_MEM_READ_H;
														next_mem_state <= `SEQ_GRAL_ALU; // read then alu
													end
												else
													next_state <= `SEQ_GRAL_ALU; // no read
											end
									endcase
								end
							`REL8:
								begin
									state <= `SEQ_PC_READ_L; // loads address
									if (dec_o_p1_optype == `OP_JSR) // bsr
										next_state <= `SEQ_JSR_PUSH;
									else
										next_state <= `SEQ_JMP_LOAD_PC; // offset loaded in this cycle, jump if needed
								end
							`REL16:
								begin
									state <= `SEQ_PC_READ_H; // loads address
									if (dec_o_p1_optype == `OP_JSR) // lbsr
										next_state <= `SEQ_JSR_PUSH;
									else
										next_state <= `SEQ_JMP_LOAD_PC;
								end
						endcase
					end
				`SEQ_DECODE_P23:
					begin // has prefix 10 or 11
						case (dec_o_p1_mode)
							`NONE: // unknown k_opcode... re-fetch ?
								state <= `SEQ_FETCH;
							`IMMEDIATE:	// 8 or 16 bits as result decides..
								begin
									case (k_opcode)
										8'h1e: begin k_write_exg <= 1; state <= `SEQ_TFREXG; end
										8'h1f: begin k_write_tfr <= 1; state <= `SEQ_TFREXG; end
										default: 
											begin
												next_state <= `SEQ_GRAL_ALU;
												if (dec_o_alu_size)
													state <= `SEQ_PC_READ_H;
												else
													state <= `SEQ_PC_READ_L;
										end
									endcase
								end
							`INHERENT:
								case (k_opcode)
									8'h3f: if (k_p2_valid) state <= `SEQ_SWI2;
										   else state <= `SEQ_SWI3;
									default: state <= `SEQ_GRAL_ALU;
								endcase
							`DIRECT:
								begin
									state <= `SEQ_PC_READ_L;
									k_mem_dest <= `MEMDEST_MH; // operand to memlo/memhi
									if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
										(dec_o_left_path_addr == `RN_MEM8))
										begin
											next_state <= `SEQ_MEM_READ_H;
											next_mem_state <= `SEQ_GRAL_ALU; // read then alu
										end
									else
										next_state <= `SEQ_GRAL_ALU; // no read
									k_eahi <= regs_o_dp;
								end
							`INDEXED:
								state <= `SEQ_IND_READ_EA;
							`EXTENDED:
								begin
									state <= `SEQ_PC_READ_H; // loads address
									k_mem_dest <= `MEMDEST_MH; // operand to memlo/memhi
									if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
										(dec_o_left_path_addr == `RN_MEM8))
										begin
											next_state <= `SEQ_MEM_READ_H;
											next_mem_state <= `SEQ_GRAL_ALU; // read then alu
										end
									else
										next_state <= `SEQ_GRAL_ALU; // no read
								end
							`REL16:
								begin // long branches only
									state <= `SEQ_PC_READ_H; // loads address
									next_state <= `SEQ_JMP_LOAD_PC;
								end
						endcase
					end
				`SEQ_GRAL_ALU:
					begin
						if (!k_mul_cnt)
							begin
								state <= `SEQ_GRAL_WBACK;
								k_write_dest <= 1; /* write destination on wback */
							end
						k_mul_cnt <= 1'h0;
					end
				`SEQ_GRAL_WBACK:
					begin
						next_mem_state <= `SEQ_FETCH;
						casex (k_opcode)
							8'h3C: state <= `SEQ_CWAI_STACK; // CWAI
							default:
								case (dec_o_dest_reg_addr)
									`RN_MEM8: state <= `SEQ_MEM_WRITE_L;
									`RN_MEM16: state <= `SEQ_MEM_WRITE_H;
									default: 
										begin 
											state <= `SEQ_FETCH; 
											k_write_post_incdec <= dec_o_ea_wpost & (dec_o_p1_mode == `INDEXED); 
										end
								endcase
						endcase
					end
				`SEQ_CWAI_STACK:
					begin
						k_pp_regs <= 8'hff;
						k_set_e <= 1;
						state <= `SEQ_PREPUSH; // first stack the registers
						next_push_state <= `SEQ_CWAI_WAIT; // wait for interrupts
					end
				`SEQ_CWAI_WAIT: /* waits for an interrupt and process it */
					begin
						k_forced_mem_size <= 1;
						next_mem_state <= `SEQ_FETCH; // then continue fetching instructions
						k_eahi <= 8'hff;
						k_ealo[7:4] <= 4'hf;
						if (k_nmi_req)
							begin
								k_reg_nmi <= 3'h0;
								k_ealo[3:0] <= 4'hc;
								state <= `SEQ_MEM_READ_H; // load new PC
							end
						else
						if (k_firq_req & `FLAGF)
							begin
								k_reg_firq <= 3'h0;
								k_ealo[3:0] <= 4'h6;
								state <= `SEQ_MEM_READ_H; // load new PC
							end
						else
						if (k_irq_req & `FLAGI)
							begin
								k_reg_irq <= 3'h0;
								k_ealo[3:0] <= 4'h8;
								state <= `SEQ_MEM_READ_H; // load new PC
							end
					end
				`SEQ_SYNC: /* sync works like this: 
				            * waits for an interrupt request
							* we recognize an interrupt if the level was kept for 2 cycles
				            * then we don't call the service routine
							* if it was 3 or more cycles, then we call the service routine
							*/
					begin
						if (k_nmi_req)
							begin
								if (k_reg_nmi == 3'b111) // at least 3 cycles long
									state <= `SEQ_NMI;
								else
									begin
										state <= `SEQ_FETCH;
										k_reg_nmi <= 3'h0;
									end
							end
						else
						if (k_firq_req & `FLAGF)
							begin
								if (k_reg_firq == 3'b111) // at least 3 cycles long
									state <= `SEQ_FIRQ;
								else
									begin
										state <= `SEQ_FETCH;
										k_reg_firq <= 3'h0;
									end
							end
						else
						if (k_irq_req & `FLAGI)
							begin
								if (k_reg_irq == 3'b111) // at least 3 cycles long
									state <= `SEQ_IRQ;
								else
									begin
										state <= `SEQ_FETCH;
										k_reg_irq <= 3'h0;
									end
							end
						else
							begin
								state <= `SEQ_FETCH_1;
								k_cpu_addr <= regs_o_pc;
							end
					end
				`SEQ_TFREXG:
					state <= `SEQ_FETCH;
				`SEQ_IND_READ_EA: // reads EA byte
					begin
						k_cpu_addr <= regs_o_pc;
						state <= `SEQ_IND_READ_EA_1;
						k_inc_pc <= 1;
					end
				`SEQ_IND_READ_EA_1:
					begin
						k_cpu_oe <= 1; // read
						state <= `SEQ_IND_READ_EA_2;
					end
				`SEQ_IND_READ_EA_2:
					begin
						k_ind_ea <= cpu_data_i;
						state <= `SEQ_IND_DECODE;
					end
				`SEQ_IND_DECODE: // here we have to see what we need for indexed...
					begin
						k_indirect_loaded <= 1'b0;
						if (dec_o_ea_ofs8)
							begin // load 1 byte offset
								state <= `SEQ_PC_READ_L;
								next_state <= `SEQ_IND_DECODE_OFS; // has some offset, load arg
							end
						else
							if (dec_o_ea_ofs16)
								begin // load 2 bytes offset
									state <= `SEQ_PC_READ_H;
									next_state <= `SEQ_IND_DECODE_OFS; // has some offset, load arg
								end
							else
								if (dec_o_p1_optype == `OP_JSR) // jsr
									begin
										next_state <= `SEQ_JSR_PUSH;
									end
								else											
									begin // no extra load...
										if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
											(dec_o_left_path_addr == `RN_MEM8))
											begin
												k_mem_dest <= `MEMDEST_MH; // operand lands in k_memhi/lo
												next_mem_state <= `SEQ_GRAL_ALU;
												state <= `SEQ_MEM_READ_H;
												if (dec_o_ea_indirect)
													k_forced_mem_size <= 1; // to load indirect address
											end
										else
											state <= `SEQ_GRAL_ALU; // no load, then store
									end
					end
				`SEQ_IND_DECODE_OFS: // loads argument if needed
					begin
						if (dec_o_p1_optype == `OP_JSR) // jsr
							begin
								next_state <= `SEQ_JSR_PUSH;
							end
						else
							begin
								if ((dec_o_right_path_addr == `RN_MEM8) || (dec_o_right_path_addr == `RN_MEM16) ||
									(dec_o_left_path_addr == `RN_MEM8))
									begin
										k_mem_dest <= `MEMDEST_MH; // operand land in k_memhi/lo
										next_mem_state <= `SEQ_GRAL_ALU;
										state <= `SEQ_MEM_READ_H;
										if (dec_o_ea_indirect)
											k_forced_mem_size <= 1; // to load indirect address
									end
								else
									state <= `SEQ_GRAL_ALU; // no load, then store
							end
					end
				`SEQ_JMP_LOAD_PC:
					begin
						state <= `SEQ_FETCH;
					end
				`SEQ_JSR_PUSH:
					begin
						k_pp_active_reg <= `RN_PC; // push PC
						state <= `SEQ_PUSH_WRITE_L;
						next_state <= `SEQ_JMP_LOAD_PC;
					end
				`SEQ_PREPUSH:
					begin
						next_state <= `SEQ_PREPUSH;
						if (k_pp_regs > 0)
							begin
								state <= `SEQ_PUSH_WRITE_L;
							end
						else
							state <= next_push_state;
						if (k_pp_regs[7]) begin k_pp_regs[7] <= 0; k_pp_active_reg <= `RN_PC; end
						else
						if (k_pp_regs[6]) begin k_pp_regs[6] <= 0; k_pp_active_reg <= (dec_o_use_s) ? `RN_U:`RN_S; end
						else
						if (k_pp_regs[5]) begin k_pp_regs[5] <= 0; k_pp_active_reg <= `RN_IY; end
						else
						if (k_pp_regs[4]) begin k_pp_regs[4] <= 0; k_pp_active_reg <= `RN_IX; end
						else
						if (k_pp_regs[3]) begin k_pp_regs[3] <= 0; k_pp_active_reg <= `RN_DP; end
						else
						if (k_pp_regs[2]) begin k_pp_regs[2] <= 0; k_pp_active_reg <= `RN_ACCB; end
						else
						if (k_pp_regs[1]) begin k_pp_regs[1] <= 0; k_pp_active_reg <= `RN_ACCA; end
						else
						if (k_pp_regs[0]) begin k_pp_regs[0] <= 0; k_pp_active_reg <= `RN_CC; end
					end
				`SEQ_PREPULL:
					begin
						if (k_pp_regs != 8'h0)
							begin
								k_mem_dest <= `MEMDEST_MH;
								next_mem_state <= `SEQ_PREPULL;
							end
						else
							state <= `SEQ_FETCH; // end of sequence
						if (k_pp_regs[0]) begin k_pp_active_reg <= `RN_CC; k_pp_regs[0] <= 0; state <= `SEQ_MEM_READ_L; end
						else
						if ((k_opcode == 8'h3B) && (!`FLAGE)) // not all registers have to be pulled
							begin
								k_pp_active_reg <= `RN_PC;  k_pp_regs <= 0; state <= `SEQ_MEM_READ_H;
							end
						else
						if (k_pp_regs[1]) begin k_pp_active_reg <= `RN_ACCA; k_pp_regs[1] <= 0; state <= `SEQ_MEM_READ_L; end
						else
						if (k_pp_regs[2]) begin k_pp_active_reg <= `RN_ACCB; k_pp_regs[2] <= 0; state <= `SEQ_MEM_READ_L; end
						else
						if (k_pp_regs[3]) begin k_pp_active_reg <= `RN_DP; k_pp_regs[3] <= 0; state <= `SEQ_MEM_READ_L; end
						else
						if (k_pp_regs[4]) begin k_pp_active_reg <= `RN_IX; k_pp_regs[4] <= 0; state <= `SEQ_MEM_READ_H;end
						else
						if (k_pp_regs[5]) begin k_pp_active_reg <= `RN_IY; k_pp_regs[5] <= 0; state <= `SEQ_MEM_READ_H;end
						else
						if (k_pp_regs[6]) begin k_pp_active_reg <= (dec_o_use_s) ? `RN_U:`RN_S; k_pp_regs[6] <= 0; state <= `SEQ_MEM_READ_H; end
						else
						if (k_pp_regs[7]) begin k_pp_active_reg <= `RN_PC;  k_pp_regs[7] <= 0; state <= `SEQ_MEM_READ_H; end
					end
				`SEQ_PUSH_WRITE_L: // first low byte push 
					begin
						k_cpu_data_o <= regs_o_left_path_data[7:0];
						state <= `SEQ_PUSH_WRITE_L_1;
						k_cpu_we <= 1; // write
						k_cpu_addr <= regs_o_su - 16'h1;
						k_dec_su <= 1;
					end
				`SEQ_PUSH_WRITE_L_1:
					begin
						if (k_pp_active_reg < `RN_ACCA)
							state <= `SEQ_PUSH_WRITE_H;
						else
							if (k_pp_regs[3:0] > 0)
								state <= `SEQ_PREPUSH;
							else
								state <= next_push_state;
						k_cpu_addr <= k_cpu_addr - 16'h1; // when pushing 16 bits the second decrement comes too late 
					end
				`SEQ_PUSH_WRITE_H: // reads high byte
					begin
						k_cpu_data_o <= regs_o_left_path_data[15:8];
						state <= `SEQ_PUSH_WRITE_H_1;
						k_cpu_we <= 1; // write
						if (k_pp_active_reg >= `RN_ACCA)
							k_cpu_addr <= regs_o_su; // address for 8 bit register
						k_dec_su <= 1; // decrement stack pointer
					end
				`SEQ_PUSH_WRITE_H_1:
					begin
						if (next_state == `SEQ_JMP_LOAD_PC)
							k_write_pc <= 1; // load PC in the next cycle, the mux output will have the right source
						state <= next_state;
					end
				`SEQ_PC_READ_H: // reads high byte for [PC], used by IMM, DIR, EXT
					begin
						k_cpu_addr <= regs_o_pc;
						state <= `SEQ_PC_READ_H_1;
						k_inc_pc <= 1;
					end
				`SEQ_PC_READ_H_1:
					begin
						k_cpu_oe <= 1; // read
						state <= `SEQ_PC_READ_H_2;
					end
				`SEQ_PC_READ_H_2:
					begin
						case (dec_o_p1_mode)
							`REL16, `IMMEDIATE: k_memhi <= cpu_data_i;
							`EXTENDED: k_eahi <= cpu_data_i;
							`INDEXED: k_ofshi <= cpu_data_i;
						endcase
						state <= `SEQ_PC_READ_L;
					end
				`SEQ_PC_READ_L: // reads low byte [PC]
					begin
						k_cpu_addr <= regs_o_pc;
						state <= `SEQ_PC_READ_L_1;
						k_inc_pc <= 1;
					end
				`SEQ_PC_READ_L_1:
					begin
						k_cpu_oe <= 1; // read
						state <= `SEQ_PC_READ_L_2;
					end
				`SEQ_PC_READ_L_2:
					begin
						case (dec_o_p1_mode)
							`NONE: k_pp_regs <= cpu_data_i; // push & pull
							`REL8, `REL16, `IMMEDIATE: k_memlo <= cpu_data_i;
							`DIRECT, `EXTENDED: k_ealo <= cpu_data_i;
							`INDEXED: k_ofslo <= cpu_data_i;
						endcase
						if ((next_state == `SEQ_JMP_LOAD_PC) & (dec_o_cond_taken))
							k_write_pc <= 1; // load PC in the next cycle, the mux output will have the right source
						state <= next_state;
					end
				`SEQ_MEM_READ_H: // reads high byte
					begin
						case (dec_o_p1_mode)
							`NONE: begin k_cpu_addr <= regs_o_su; k_inc_su <= 1; end // pull, rts, rti
							`INDEXED: 
								if (k_indirect_loaded)
									k_cpu_addr <= { k_memhi, k_memlo };
								else
									k_cpu_addr <= regs_o_eamem_addr;
							default: k_cpu_addr <= { k_eahi, k_ealo };
						endcase
						if (k_forced_mem_size | dec_o_source_size | (k_pp_active_reg <  `RN_ACCA))
							state <= `SEQ_MEM_READ_H_1;
						else
							state <= `SEQ_MEM_READ_L_1;
						k_forced_mem_size <= 0; // used for vector fetch
					end
				`SEQ_MEM_READ_H_1:
					begin
						k_cpu_oe <= 1; // read
						state <= `SEQ_MEM_READ_H_2;
					end
				`SEQ_MEM_READ_H_2:
					begin
						case (k_mem_dest)
							`MEMDEST_PC,//: k_new_pc[15:8] <= cpu_data_i;
							`MEMDEST_MH: k_memhi <= cpu_data_i;
							`MEMDEST_AH: k_eahi <= cpu_data_i;
						endcase
						state <= `SEQ_MEM_READ_L_1;
						k_cpu_addr  <= k_cpu_addr + 16'h1;
						case (dec_o_p1_mode)
							`NONE: begin k_inc_su <= 1; end // pull, rts, rti
						endcase
					end
				`SEQ_MEM_READ_L: // reads low byte
					begin
						// falls through from READ_MEM_H with the right address
						case (dec_o_p1_mode)
							`NONE: begin k_cpu_addr <= regs_o_su; k_inc_su <= 1; end // pull, rts, rti
						endcase
						state <= `SEQ_MEM_READ_L_1;
					end
				`SEQ_MEM_READ_L_1:
					begin
						k_cpu_oe <= 1; // read
						state <= `SEQ_MEM_READ_L_2;
					end
				`SEQ_MEM_READ_L_2:
					begin
						case (k_mem_dest)
							`MEMDEST_PC,
							`MEMDEST_MH: k_memlo <= cpu_data_i;
							`MEMDEST_AH: k_ealo <= cpu_data_i;
						endcase
						case (dec_o_p1_mode)
							`NONE, `INHERENT: k_write_dest <= 1; // pull, rts, rti
						endcase
						if (next_mem_state == `SEQ_LOADPC)
							k_write_pc <= 1;
						case (dec_o_p1_mode)
							`INDEXED: // address loaded, load argument
								if (k_indirect_loaded | (!dec_o_ea_indirect))
									state <= next_mem_state;
								else
									begin
										state <= `SEQ_MEM_READ_H;
										k_indirect_loaded <= 1'b1;
									end
							default:
								state <= next_mem_state;
						endcase
					end
				`SEQ_MEM_WRITE_H: // writes high byte
					begin
						case (dec_o_p1_mode)
							`INDEXED: k_cpu_addr <= regs_o_eamem_addr;
							default: k_cpu_addr <= { k_eahi, k_ealo };
						endcase
						k_cpu_data_o <= datamux_o_dest[15:8];
						state <= `SEQ_MEM_WRITE_H_1;
						k_cpu_we <= 1; // read
					end
				`SEQ_MEM_WRITE_H_1:
					begin
						state <= `SEQ_MEM_WRITE_L;
						k_cpu_addr <= k_cpu_addr + 16'h1;
					end
				`SEQ_MEM_WRITE_L: // reads high byte
					begin
						if (!dec_o_alu_size) // only if it is an 8 bit write
							case (dec_o_p1_mode)
								`INDEXED: k_cpu_addr <= regs_o_eamem_addr;
								default: k_cpu_addr <= { k_eahi, k_ealo };
							endcase
						k_cpu_data_o <= datamux_o_dest[7:0];
						state <= `SEQ_MEM_WRITE_L_1;
						k_cpu_we <= 1; // write
					end
				`SEQ_MEM_WRITE_L_1:
					begin
						k_write_post_incdec <= dec_o_ea_wpost; 
						state <= next_mem_state;
					end
				
			endcase
		end
	end
	
initial
	begin
		k_cpu_oe = 0;
		k_cpu_we = 0;
		k_mem_dest = 0;
		k_new_pc = 16'hffff;
		k_write_tfr = 0;
		k_write_exg = 0;
		k_mul_cnt = 0;
		k_write_dest = 0;
		k_indirect_loaded = 0;
	end
endmodule

MC6809/HD6309 compatible core.

Simulation can be done with icarus verilog.

$ iverilog tb.v ../rtl/verilog/*.v
$ vvp a.out

a dump file dump.vcd will be created. This file can be viewed with GTKWave.
Simulation with other tools is also possible.
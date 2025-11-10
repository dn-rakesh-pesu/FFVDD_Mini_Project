// =====================================================================
// Layered Testbench for Ethernet MAC Verification (EDA Playground Ready)
// DUT module name: ethernet_mac_dut
// With VCD dump for waveform viewing (EPWave)
// ====================================================================
class mac_transaction;
  rand bit [47:0] data;
  rand bit        valid;

  function void display(string tag);
    $display("[%0t][%s] DATA = %h VALID = %0b", $time, tag, data, valid);
  endfunction
endclass

// ---------------------------------------------------
class mac_generator;
  mailbox gen2drv;
  int num_trans = 5;

  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task run();
    mac_transaction tr;
    repeat (num_trans) begin
      tr = new();
      assert(tr.randomize() with { valid == 1; });
      tr.display("GEN");
      gen2drv.put(tr);
      #10;
    end
  endtask
endclass

// ---------------------------------------------------
interface mac_if(input logic clk);
  logic rst_n;
  logic [47:0] tx_data;
  logic tx_valid;
  logic [47:0] rx_data;
  logic rx_valid;
endinterface

// ---------------------------------------------------
class mac_driver;
  virtual mac_if vif;
  mailbox gen2drv;

  function new(virtual mac_if vif, mailbox gen2drv);
    this.vif = vif;
    this.gen2drv = gen2drv;
  endfunction

  task run();
    mac_transaction tr;
    forever begin
      gen2drv.get(tr);
      vif.tx_valid <= tr.valid;
      vif.tx_data  <= tr.data;
      tr.display("DRV");
      @(posedge vif.clk);
      vif.tx_valid <= 0;
    end
  endtask
endclass

// ---------------------------------------------------
class mac_monitor;
  virtual mac_if vif;
  mailbox mon2scb;

  function new(virtual mac_if vif, mailbox mon2scb);
    this.vif = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    mac_transaction tr;
    forever begin
      @(posedge vif.clk);
      if (vif.rx_valid) begin
        tr = new();
        tr.data  = vif.rx_data;
        tr.valid = vif.rx_valid;
        tr.display("MON");
        mon2scb.put(tr);
      end
    end
  endtask
endclass

// ---------------------------------------------------
class mac_scoreboard;
  mailbox mon2scb;
  int pass = 0, fail = 0;

  function new(mailbox mon2scb);
    this.mon2scb = mon2scb;
  endfunction

  task run();
    mac_transaction tr;
    forever begin
      mon2scb.get(tr);
      if (tr.valid) begin
        pass++;
        $display("[SCB] PASS: Data received correctly: %h", tr.data);
      end else begin
        fail++;
        $display("[SCB] FAIL: Invalid transaction");
      end
    end
  endtask
endclass

// ---------------------------------------------------
class mac_env;
  mac_generator gen;
  mac_driver drv;
  mac_monitor mon;
  mac_scoreboard scb;

  mailbox gen2drv, mon2scb;
  virtual mac_if vif;

  function new(virtual mac_if vif);
    this.vif = vif;
    gen2drv = new();
    mon2scb = new();

    gen = new(gen2drv);
    drv = new(vif, gen2drv);
    mon = new(vif, mon2scb);
    scb = new(mon2scb);
  endfunction

  task run();
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
    join_none
  endtask
endclass

// ---------------------------------------------------
module testbench;
  logic clk;
  mac_if vif(clk);

  // Instantiate DUT
  ethernet_mac_dut dut (
    .clk(clk),
    .rst_n(vif.rst_n),
    .tx_data(vif.tx_data),
    .tx_valid(vif.tx_valid),
    .rx_data(vif.rx_data),
    .rx_valid(vif.rx_valid)
  );

  mac_env env;

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Main test
  initial begin
    // Dump waveform for EPWave
    $dumpfile("dump.vcd");
    $dumpvars(0, testbench);

    // Reset and start environment
    vif.rst_n = 0;
    vif.tx_valid = 0;
    #20 vif.rst_n = 1;

    env = new(vif);
    env.run();

    #300 $finish;
  end
endmodule

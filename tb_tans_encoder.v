`timescale 1ns/1ps

// ============================================================================
// Testbench: tb_tans_encoder
// Descricao: Valida o Encoder tANS didatico (L=16, R=4, 3 simbolos) comparando
//            cada passo (nbBits, bits extraidos, proximo estado) e os bytes
//            empacotados com os vetores gerados pelo modelo de referencia Python.
// ============================================================================

module tb_tans_encoder;

    localparam L          = 16;
    localparam R          = 4;
    localparam SYM_WIDTH  = 2;
    localparam NUM_SYMS   = 4;
    localparam NB_WIDTH   = 3;
    localparam NB_PARAM_W = 8;
    localparam NUM_VECS   = 12;
    localparam NUM_BYTES  = 3;

    reg                   clk;
    reg                   rst_n;
    reg                   init_en;
    reg  [R:0]            init_state;
    reg                   sym_valid;
    reg  [SYM_WIDTH-1:0]  sym_in;
    reg                   sym_last;

    wire                  step_valid;
    wire [R-1:0]          step_bits;
    wire [NB_WIDTH-1:0]   step_nbits;
    wire                  step_last;
    wire                  byte_valid;
    wire [7:0]            byte_out;
    wire                  byte_last;
    wire [3:0]            byte_last_bits;
    wire [R:0]            final_state;
    wire                  core_done;

    // Vetores de teste: [15:12]=sym, [11:8]=nbBits, [7:4]=out_bits, [3:0]=next_state[3:0] -> 20 bits
    reg [19:0] test_vecs [0:NUM_VECS-1];
    reg [7:0]  exp_bytes [0:NUM_BYTES-1];

    integer errors;
    integer step_idx;
    integer byte_idx;
    integer i;

    tans_encoder_top #(
        .L                 (L),
        .R                 (R),
        .SYM_WIDTH         (SYM_WIDTH),
        .NUM_SYMS          (NUM_SYMS),
        .NB_WIDTH          (NB_WIDTH),
        .NB_PARAM_W        (NB_PARAM_W),
        .LUT_SYM_NB_FILE   ("lut_sym_nb.txt"),
        .LUT_SYM_OFF_FILE  ("lut_sym_off.txt"),
        .LUT_ENC_TABLE_FILE("lut_enc_table.txt")
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .init_en       (init_en),
        .init_state    (init_state),
        .sym_valid     (sym_valid),
        .sym_in        (sym_in),
        .sym_last      (sym_last),
        .tbl_wr_en     (1'b0),
        .tbl_wr_sel    (2'b00),
        .tbl_wr_addr   ({R{1'b0}}),
        .tbl_wr_data   ({NB_PARAM_W{1'b0}}),
        .step_valid    (step_valid),
        .step_bits     (step_bits),
        .step_nbits    (step_nbits),
        .step_last     (step_last),
        .byte_valid    (byte_valid),
        .byte_out      (byte_out),
        .byte_last     (byte_last),
        .byte_last_bits(byte_last_bits),
        .final_state   (final_state),
        .core_done     (core_done)
    );

    // Clock de 100 MHz (periodo 10 ns)
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Monitor de passos e bytes
    always @(posedge clk) begin
        if (rst_n) begin
            if (step_valid) begin
                begin : chk_step
                    reg [2:0] exp_nb;
                    reg [3:0] exp_bits;
                    reg [4:0] exp_next;
                    exp_nb   = test_vecs[step_idx][14:12];
                    exp_bits = test_vecs[step_idx][11:8];
                    exp_next = test_vecs[step_idx][4:0];

                    $display("[STEP %2d] sym=%0d | nbBits=%0d (exp=%0d) | out_bits=%b (exp=%b) | next_state=%2d (exp=%2d)%s",
                             step_idx, test_vecs[step_idx][17:16],
                             step_nbits, exp_nb,
                             step_bits, exp_bits,
                             final_state, exp_next,
                             step_last ? " [LAST]" : "");

                    if (step_nbits !== exp_nb) begin
                        $display("  ERRO nbBits no passo %0d: obtido %0d, esperado %0d", step_idx, step_nbits, exp_nb);
                        errors = errors + 1;
                    end
                    if (step_bits !== exp_bits) begin
                        $display("  ERRO out_bits no passo %0d: obtido %b, esperado %b", step_idx, step_bits, exp_bits);
                        errors = errors + 1;
                    end
                    if (final_state !== exp_next) begin
                        $display("  ERRO next_state no passo %0d: obtido %0d, esperado %0d", step_idx, final_state, exp_next);
                        errors = errors + 1;
                    end
                    step_idx = step_idx + 1;
                end
            end

            if (byte_valid) begin
                $display("[BYTE %2d] byte_out=0x%02x (exp=0x%02x) | last=%0b | last_valid_bits=%0d",
                         byte_idx, byte_out, exp_bytes[byte_idx], byte_last, byte_last_bits);
                if (byte_out !== exp_bytes[byte_idx]) begin
                    $display("  ERRO byte %0d: obtido 0x%02x, esperado 0x%02x", byte_idx, byte_out, exp_bytes[byte_idx]);
                    errors = errors + 1;
                end
                byte_idx = byte_idx + 1;
            end
        end
    end

    task run_block_test;
        input use_gaps;
        begin
            step_idx = 0;
            byte_idx = 0;

            if (use_gaps) begin
                // Teste 2: init_en antes do primeiro simbolo e pausas entre simbolos
                @(negedge clk);
                init_en    = 1'b1;
                init_state = 5'd16;
                sym_valid  = 1'b0;
                sym_in     = 2'd0;
                sym_last   = 1'b0;
                @(posedge clk);

                for (i = 0; i < NUM_VECS; i = i + 1) begin
                    @(negedge clk);
                    init_en   = 1'b0;
                    sym_valid = 1'b1;
                    sym_in    = test_vecs[i][17:16];
                    sym_last  = (i == NUM_VECS - 1);
                    @(posedge clk);

                    // Ciclo ocioso no meio
                    if (i == 3 || i == 7) begin
                        @(negedge clk);
                        sym_valid = 1'b0;
                        sym_last  = 1'b0;
                        @(posedge clk);
                    end
                end
            end else begin
                // Teste 1: streaming continuo (1 simbolo por ciclo, init_en no 1o simbolo)
                for (i = 0; i < NUM_VECS; i = i + 1) begin
                    @(negedge clk);
                    init_en    = (i == 0);
                    init_state = 5'd16;
                    sym_valid  = 1'b1;
                    sym_in     = test_vecs[i][17:16];
                    sym_last   = (i == NUM_VECS - 1);
                    @(posedge clk);
                end
            end

            @(negedge clk);
            init_en   = 1'b0;
            sym_valid = 1'b0;
            sym_in    = 2'd0;
            sym_last  = 1'b0;

            // Aguarda flush do bit packer
            repeat (4) @(posedge clk);

            if (step_idx !== NUM_VECS) begin
                $display("ERRO: esperados %0d passos, recebidos %0d", NUM_VECS, step_idx);
                errors = errors + 1;
            end
            if (byte_idx !== NUM_BYTES) begin
                $display("ERRO: esperados %0d bytes, recebidos %0d", NUM_BYTES, byte_idx);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_tans_encoder.vcd");
        $dumpvars(0, tb_tans_encoder);

        $readmemh("test_vectors.txt", test_vecs);
        $readmemh("expected_bytes.txt", exp_bytes);

        errors     = 0;
        rst_n      = 1'b0;
        init_en    = 1'b0;
        init_state = 5'd16;
        sym_valid  = 1'b0;
        sym_in     = 2'd0;
        sym_last   = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        $display("\n=== TESTE 1: Streaming continuo (1 simbolo/ciclo) ===");
        run_block_test(1'b0);

        $display("\n=== TESTE 2: Init antecipado + ciclos ociosos ===");
        run_block_test(1'b1);

        if (errors == 0) begin
            $display("\n[SUCESSO] Todos os passos, estados e bytes bateram 100%% com o modelo Python!");
        end else begin
            $display("\n[FALHA] Foram encontrados %0d erros.", errors);
        end

        $finish;
    end

endmodule

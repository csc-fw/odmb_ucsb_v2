-- PCFIFO: Takes the DDU packets, and Produces continuous packets suitable for ethernet

library ieee;
library unisim;
library unimacro;
library hdlmacro;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_1164.all;
use unisim.vcomponents.all;
use unimacro.vcomponents.all;
use hdlmacro.hdlmacro.all;

entity pcfifo is
  generic (
    NFIFO : integer range 1 to 16 := 16);  -- Number of FIFOs in PCFIFO
  port(

    clk_in  : in std_logic;
    clk_out : in std_logic;
    rst     : in std_logic;

    tx_ack : in std_logic;

    dv_in   : in std_logic;
    ld_in   : in std_logic;
    data_in : in std_logic_vector(15 downto 0);

    dv_out   : out std_logic;
    data_out : out std_logic_vector(15 downto 0)
    );

end pcfifo;


architecture pcfifo_architecture of pcfifo is

  component PULSE_EDGE is
    port (
      DOUT   : out std_logic;
      PULSE1 : out std_logic;
      CLK    : in  std_logic;
      RST    : in  std_logic;
      NPULSE : in  integer;
      DIN    : in  std_logic
      );
  end component;

  constant logich : std_logic := '1';

  type   fsm_state_type is (IDLE, FIFO_TX, FIFO_TX_HEADER, IDLE_ETH);
  signal f0_current_state : fsm_state_type := IDLE;
  signal f0_next_state    : fsm_state_type := IDLE;

  signal f0_rden  : std_logic;
  signal f0_empty : std_logic;
  signal f0_out   : std_logic_vector(15 downto 0);
  signal f0_ld    : std_logic;

  signal ld_in_q, ld_in_pulse : std_logic                    := '0';
  signal ld_out, ld_out_pulse : std_logic                    := '0';
  signal tx_ack_q             : std_logic_vector(2 downto 0) := (others => '0');
  signal tx_ack_q_b           : std_logic                    := '1';

  type   fifo_data_type is array (NFIFO downto 1) of std_logic_vector(17 downto 0);
  signal fifo_in, fifo_out                 : fifo_data_type;
  signal fifo_aempty                       : std_logic_vector(NFIFO downto 1);
  signal fifo_afull                        : std_logic_vector(NFIFO downto 1);
  signal fifo_empty                        : std_logic_vector(NFIFO downto 1);
  signal fifo_full                         : std_logic_vector(NFIFO downto 1);
  signal fifo_wren, fifo_wrck : std_logic_vector(NFIFO downto 1);
  signal fifo_rden, fifo_rdck              : std_logic_vector(NFIFO downto 1);
  type   fifo_cnt_type is array (NFIFO downto 1) of std_logic_vector(10 downto 0);
  signal fifo_wr_cnt, fifo_rd_cnt          : fifo_cnt_type;

  signal pck_cnt_out : std_logic_vector(7 downto 0) := (others => '0');
  signal int_clk     : std_logic                    := '0';

  -- IDLE_ETH ensures the interframe gap of 96 bits between packets
  signal idle_cnt_en, idle_cnt_rst : std_logic            := '0';
  signal idle_cnt                  : integer range 0 to 9 := 0;

  signal dv_in_pulse : std_logic := '0';
  signal first_in, first_dly : std_logic := '1';

  signal pck_cnt_total : std_logic_vector(15 downto 0) := (others => '0');
  
begin

-- Generation of counter for total packets sent
  DV_PULSE_EDGE : pulse_edge port map(dv_in_pulse, open, clk_in, rst, 1, dv_in);
  FDLDIN            : FD port map(ld_in_q, clk_in, ld_in);
  pck_cnt_total_pro : process (ld_in, rst, clk_in)
  begin
    if (rst = '1') then
      pck_cnt_total <= (others => '0');
    elsif (rising_edge(clk_in)) then
      if (ld_in = '1') then
        pck_cnt_total <= pck_cnt_total + 1;
      end if;
    end if;
  end process;


-- FIFOs
  FDFIRST : FDCP port map(first_in, ld_in_q, dv_in_pulse, logich, rst);
  
  int_clk          <= clk_in;
  fifo_wrck(NFIFO) <= clk_in;
  fifo_wren(NFIFO) <= dv_in or ld_in_q;
  fifo_in(NFIFO)   <= first_in & '0' & data_in when ld_in_q = '0' else "01" & pck_cnt_total;

  fifo_rdck(NFIFO) <= int_clk;
  fifo_rden(NFIFO) <= not (fifo_empty(NFIFO) or fifo_full(NFIFO-1));


  FIFO_M_NFIFO : FIFO_DUALCLOCK_MACRO
    generic map (
      DEVICE                  => "VIRTEX6",  -- Target Device: "VIRTEX5", "VIRTEX6" 
      ALMOST_FULL_OFFSET      => X"0080",    -- Sets almost full threshold
      ALMOST_EMPTY_OFFSET     => X"0080",    -- Sets the almost empty threshold
      DATA_WIDTH              => 18,  -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
      FIFO_SIZE               => "36Kb",     -- Target BRAM, "18Kb" or "36Kb" 
      FIRST_WORD_FALL_THROUGH => true)  -- Sets the FIFO FWFT to TRUE or FALSE

    port map (
      ALMOSTEMPTY => fifo_aempty(NFIFO),  -- Output almost empty 
      ALMOSTFULL  => fifo_afull(NFIFO),   -- Output almost full
      DO          => fifo_out(NFIFO),     -- Output data
      EMPTY       => fifo_empty(NFIFO),   -- Output empty
      FULL        => fifo_full(NFIFO),    -- Output full
      RDCOUNT     => fifo_rd_cnt(NFIFO),  -- Output read count
      RDERR       => open,                -- Output read error
      WRCOUNT     => fifo_wr_cnt(NFIFO),  -- Output write count
      WRERR       => open,                -- Output write error
      DI          => fifo_in(NFIFO),      -- Input data
      RDCLK       => fifo_rdck(NFIFO),    -- Input read clock
      RDEN        => fifo_rden(NFIFO),    -- Input read enable
      RST         => rst,                 -- Input reset
      WRCLK       => fifo_wrck(NFIFO),    -- Input write clock
      WREN        => fifo_wren(NFIFO)     -- Input write enable
      );

  GEN_FIFO_M : for I in NFIFO-1 downto 2 generate
  begin

    fifo_wren(I) <= not (fifo_empty(I+1) or fifo_full(I));
    fifo_wrck(I) <= int_clk;
    fifo_in(I)   <= fifo_out(I+1);
    fifo_rden(I) <= not (fifo_empty(I) or fifo_full(I-1));
    fifo_rdck(I) <= int_clk;

    FIFO_MOD : FIFO_DUALCLOCK_MACRO
      generic map (
        DEVICE                  => "VIRTEX6",  -- Target Device: "VIRTEX5", "VIRTEX6" 
        ALMOST_FULL_OFFSET      => X"0080",  -- Sets almost full threshold
        ALMOST_EMPTY_OFFSET     => X"0080",  -- Sets the almost empty threshold
        DATA_WIDTH              => 18,  -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
        FIFO_SIZE               => "36Kb",   -- Target BRAM, "18Kb" or "36Kb" 
        FIRST_WORD_FALL_THROUGH => true)  -- Sets the FIFO FWFT to TRUE or FALSE

      port map (
        ALMOSTEMPTY => fifo_aempty(I),  -- Output almost empty 
        ALMOSTFULL  => fifo_afull(I),   -- Output almost full
        DO          => fifo_out(I),     -- Output data
        EMPTY       => fifo_empty(I),   -- Output empty
        FULL        => fifo_full(I),    -- Output full
        RDCOUNT     => fifo_rd_cnt(I),  -- Output read count
        RDERR       => open,            -- Output read error
        WRCOUNT     => fifo_wr_cnt(I),  -- Output write count
        WRERR       => open,            -- Output write error
        DI          => fifo_in(I),      -- Input data
        RDCLK       => fifo_rdck(I),    -- Input read clock
        RDEN        => fifo_rden(I),    -- Input read enable
        RST         => rst,             -- Input reset
        WRCLK       => fifo_wrck(I),    -- Input write clock
        WREN        => fifo_wren(I)     -- Input write enable
        );
  end generate GEN_FIFO_M;

  fifo_wren(1) <= not (fifo_empty(2) or fifo_full(1));
  fifo_wrck(1) <= int_clk;
  fifo_in(1)   <= fifo_out(2);
  fifo_rden(1) <= f0_rden;
  fifo_rdck(1) <= clk_out;


  FIFO_M_1 : FIFO_DUALCLOCK_MACRO
    generic map (
      DEVICE                  => "VIRTEX6",  -- Target Device: "VIRTEX5", "VIRTEX6" 
      ALMOST_FULL_OFFSET      => X"0080",    -- Sets almost full threshold
      ALMOST_EMPTY_OFFSET     => X"0080",    -- Sets the almost empty threshold
      DATA_WIDTH              => 18,  -- Valid values are 1-72 (37-72 only valid when FIFO_SIZE="36Kb")
      FIFO_SIZE               => "36Kb",     -- Target BRAM, "18Kb" or "36Kb" 
      FIRST_WORD_FALL_THROUGH => false)  -- Sets the FIFO FWFT to TRUE or FALSE

    port map (
      ALMOSTEMPTY => fifo_aempty(1),    -- Output almost empty 
      ALMOSTFULL  => fifo_afull(1),     -- Output almost full
      DO          => fifo_out(1),       -- Output data
      EMPTY       => fifo_empty(1),     -- Output empty
      FULL        => fifo_full(1),      -- Output full
      RDCOUNT     => fifo_rd_cnt(1),    -- Output read count
      RDERR       => open,              -- Output read error
      WRCOUNT     => fifo_wr_cnt(1),    -- Output write count
      WRERR       => open,              -- Output write error
      DI          => fifo_in(1),        -- Input data
      RDCLK       => fifo_rdck(1),      -- Input read clock
      RDEN        => fifo_rden(1),      -- Input read enable
      RST         => rst,               -- Input reset
      WRCLK       => fifo_wrck(1),      -- Input write clock
      WREN        => fifo_wren(1)       -- Input write enable
      );

  f0_out   <= fifo_out(1)(15 downto 0);
  f0_ld    <= fifo_out(1)(16);
  f0_empty <= fifo_empty(1);

  FDCACK   : FDC port map(tx_ack_q(0), tx_ack, tx_ack_q(2), tx_ack_q_b);
  FDACK_Q  : FD port map(tx_ack_q(1), clk_out, tx_ack_q(0));
  FDACK_QQ : FD port map(tx_ack_q(2), clk_out, tx_ack_q(1));
  tx_ack_q_b <= not tx_ack_q(2);

-- FSMs
   FIRSTDLY : SRLC32E port map(first_dly, open, "11111", logich, int_clk, fifo_in(1)(17));
  
  LDOUT_PULSE_EDGE : pulse_edge port map(ld_out_pulse, open, clk_out, rst, 1, ld_out);
  LDIN_PULSE_EDGE  : pulse_edge port map(ld_in_pulse, open, clk_out, rst, 1, first_dly);

  pck_cnt : process (ld_in_pulse, ld_out_pulse, rst, clk_out)
    variable pck_cnt_data : std_logic_vector(7 downto 0) := (others => '0');
  begin
    if (rst = '1') then
      pck_cnt_data := (others => '0');
    elsif (rising_edge(clk_out)) then
      if (ld_in_pulse = '1') and (ld_out_pulse = '0') then
        pck_cnt_data := pck_cnt_data + 1;
      elsif (ld_in_pulse = '0') and (ld_out_pulse = '1') then
        pck_cnt_data := pck_cnt_data - 1;
      end if;
    end if;

    pck_cnt_out <= pck_cnt_data;
    
  end process;

  f0_fsm_regs : process (f0_next_state, rst, clk_out, idle_cnt)
  begin
    if (rst = '1') then
      f0_current_state <= IDLE;
    elsif rising_edge(clk_out) then
      f0_current_state <= f0_next_state;
      if(idle_cnt_rst = '1') then
        idle_cnt <= 0;
      elsif(idle_cnt_en = '1') then
        idle_cnt <= idle_cnt + 1;
      end if;
    end if;
    
  end process;

  f0_fsm_logic : process (f0_current_state, f0_out, f0_empty, f0_ld, pck_cnt_out, tx_ack_q, idle_cnt)
  begin
    case f0_current_state is
      when IDLE =>
        dv_out       <= '0';
        data_out     <= (others => '0');
        ld_out       <= '0';
        idle_cnt_rst <= '0';
        idle_cnt_en  <= '0';
        if (pck_cnt_out = "00000000") then
          f0_rden       <= '0';
          f0_next_state <= IDLE;
        else
          f0_rden       <= '1';
          f0_next_state <= FIFO_TX_HEADER;
        end if;
        
      when FIFO_TX_HEADER =>
        dv_out       <= '1';
        data_out     <= f0_out;
        ld_out       <= '0';
        idle_cnt_rst <= '0';
        idle_cnt_en  <= '0';
        if (tx_ack_q(0) = '1') then
          f0_rden       <= '1';
          f0_next_state <= FIFO_TX;
        else
          f0_rden       <= '0';
          f0_next_state <= FIFO_TX_HEADER;
        end if;

      when FIFO_TX =>
        dv_out       <= '1';
        data_out     <= f0_out;
        idle_cnt_rst <= '0';
        idle_cnt_en  <= '0';
        if f0_ld = '1' then
          ld_out        <= '1';
          f0_rden       <= '0';
          f0_next_state <= IDLE_ETH;
        else
          ld_out        <= '0';
          f0_rden       <= '1';
          f0_next_state <= FIFO_TX;
        end if;

      when IDLE_ETH =>
        dv_out      <= '0';
        data_out    <= (others => '0');
        ld_out      <= '0';
        f0_rden     <= '0';
        idle_cnt_en <= '1';
        if (idle_cnt > 7) then
          f0_next_state <= IDLE;
          idle_cnt_rst  <= '1';
        else
          f0_next_state <= IDLE_ETH;
          idle_cnt_rst  <= '0';
        end if;
        
      when others =>
        dv_out        <= '0';
        data_out      <= (others => '0');
        f0_rden       <= '0';
        ld_out        <= '0';
        idle_cnt_rst  <= '0';
        idle_cnt_en   <= '0';
        f0_next_state <= IDLE;
        
    end case;
    
  end process;
  
end pcfifo_architecture;

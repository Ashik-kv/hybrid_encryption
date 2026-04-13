library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_gift64_core is
-- Testbench entities are always empty
end entity;

architecture tb of tb_gift64_core is

  -- ==========================================
  -- Component Declaration (Matches your entity)
  -- ==========================================
  component gift64_core is
    port (
      clk       : in  std_logic;
      rst_n     : in  std_logic;
      start     : in  std_logic;
      enc_dec   : in  std_logic;
      key_in    : in  std_logic_vector(127 downto 0);
      data_in   : in  std_logic_vector(63 downto 0);
      data_out  : out std_logic_vector(63 downto 0);
      done      : out std_logic
    );
  end component;

  -- ==========================================
  -- Signals connecting to the DUT
  -- ==========================================
  signal clk      : std_logic := '0';
  signal rst_n    : std_logic := '0';
  signal start    : std_logic := '0';
  signal enc_dec  : std_logic := '1';
  signal key_in   : std_logic_vector(127 downto 0) := (others => '0');
  signal data_in  : std_logic_vector(63 downto 0)  := (others => '0');
  signal data_out : std_logic_vector(63 downto 0);
  signal done     : std_logic;

  -- Clock period definition (100 MHz)
  constant CLK_PERIOD : time := 10 ns;

begin

  -- ==========================================
  -- Clock Generator
  -- ==========================================
  clk_process : process
  begin
    clk <= '0';
    wait for CLK_PERIOD / 2;
    clk <= '1';
    wait for CLK_PERIOD / 2;
  end process;

  -- ==========================================
  -- Device Under Test (DUT) Instantiation
  -- ==========================================
  dut : gift64_core
    port map (
      clk      => clk,
      rst_n    => rst_n,
      start    => start,
      enc_dec  => enc_dec,
      key_in   => key_in,
      data_in  => data_in,
      data_out => data_out,
      done     => done
    );

  -- ==========================================
  -- Main Stimulus Process
  -- ==========================================
  stimulus_process : process
    -- Known good test vectors for GIFT-64
    constant TEST_KEY   : std_logic_vector(127 downto 0) := x"fedcba9876543210fedcba9876543210";
    constant PLAINTEXT  : std_logic_vector(63 downto 0)  := x"fedcba9876543210";
    constant CIPHERTEXT : std_logic_vector(63 downto 0)  := x"c1b71f66160ff587"; 

  begin
    -- 1. Apply Reset
    rst_n   <= '0';
    start   <= '0';
    enc_dec <= '1'; 
    key_in  <= TEST_KEY;
    data_in <= PLAINTEXT;
    
    wait for CLK_PERIOD * 5;
    rst_n <= '1'; -- Release reset
    wait for CLK_PERIOD * 2;

    -- ==========================================
    -- Test 1: Encryption
    -- ==========================================
    report "--- Starting Encryption Test ---";
    enc_dec <= '1';       -- Set to Encrypt Mode
    data_in <= PLAINTEXT; -- Load Plaintext
    
    -- Pulse Start
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Wait for completion
    wait until done = '1';
    wait for CLK_PERIOD; 

    -- Verify Output
    if data_out = CIPHERTEXT then
      report "[PASS] Encryption successful. Output matches expected ciphertext.";
    else
      report "[FAIL] Encryption failed!" severity error;
    end if;

    wait for CLK_PERIOD * 5;

    -- ==========================================
    -- Test 2: Decryption
    -- ==========================================
    report "--- Starting Decryption Test ---";
    enc_dec <= '0';      -- Set to Decrypt Mode
    data_in <= data_out; -- Feed the ciphertext back into the input
    
    -- Pulse Start
    start <= '1';
    wait for CLK_PERIOD;
    start <= '0';

    -- Wait for completion
    wait until done = '1';
    wait for CLK_PERIOD; 

    -- Verify Output
    if data_out = PLAINTEXT then
      report "[PASS] Decryption successful. Output matches original plaintext.";
    else
      report "[FAIL] Decryption failed!" severity error;
    end if;

    -- ==========================================
    -- End Simulation
    -- ==========================================
    report "--- All Tests Completed ---";
    wait; -- Stop the process from looping
  end process;

end architecture;
----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/27/2026 09:17:29 AM
-- Design Name: 
-- Module Name: top_module - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
-- Module Name: top_module - Behavioral
-- Description: Unifies UART RX, GIFT-64 Core, and UART TX. (No LEDs)
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top is
  port(
    clk     : in  std_logic;
    rst_n   : in  std_logic;
    uart_rx : in  std_logic;
    uart_tx : out std_logic
  );
end entity;

architecture rtl of top is

  -- ==========================================
  -- Signals for UART Receiver & Control
  -- ==========================================
  signal rx_data   : std_logic_vector(7 downto 0);
  signal rx_valid  : std_logic;
  signal byte_cnt  : integer range 0 to 24;

  -- ==========================================
  -- Signals for GIFT Core
  -- ==========================================
  signal key_reg   : std_logic_vector(127 downto 0);
  signal data_reg  : std_logic_vector(63 downto 0);
  signal enc_reg   : std_logic;
  signal gift_start: std_logic;
  signal gift_done : std_logic;
  signal gift_out  : std_logic_vector(63 downto 0);

  -- ==========================================
  -- Signals for UART Transmitter
  -- ==========================================
  signal tx_start    : std_logic;
  signal tx_data     : std_logic_vector(7 downto 0);
  signal tx_active   : std_logic;
  signal tx_done     : std_logic;
  
  -- TX State Machine
  type tx_state_t is (TX_IDLE, TX_SEND_BYTE, TX_WAIT);
  signal tx_state    : tx_state_t;
  signal tx_byte_cnt : integer range 0 to 8;
  signal shift_out   : std_logic_vector(63 downto 0);

begin

  -- ==========================================
  -- 1. UART Receiver Instantiation
  -- ==========================================
  uart_inst : entity work.uart_rx
    port map(
      clk       => clk,
      rst_n     => rst_n,
      rx_serial => uart_rx,
      rx_data   => rx_data,
      rx_valid  => rx_valid
    );

  -- ==========================================
  -- 2. Data Assembly & Core Trigger Process
  -- ==========================================
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      byte_cnt   <= 0;
      gift_start <= '0';
      key_reg    <= (others => '0');
      data_reg   <= (others => '0');
      enc_reg    <= '1'; 
      
    elsif rising_edge(clk) then
      gift_start <= '0';

      if rx_valid = '1' then
        -- Byte 0: Mode (1=Encrypt, 0=Decrypt)
        if byte_cnt = 0 then
          enc_reg <= rx_data(0);
          
        -- Bytes 1 to 16: 128-bit Key
        elsif byte_cnt <= 16 then
          key_reg <= key_reg(119 downto 0) & rx_data;
          
        -- Bytes 17 to 24: 64-bit Plaintext/Ciphertext
        elsif byte_cnt <= 24 then
          data_reg <= data_reg(55 downto 0) & rx_data;
        end if;

        -- Trigger encryption when all 25 bytes are received
        if byte_cnt = 24 then
          gift_start <= '1';
          byte_cnt <= 0;
        else
          byte_cnt <= byte_cnt + 1;
        end if;
      end if;

    end if;
  end process;

  -- ==========================================
  -- 3. GIFT-64 Core Instantiation
  -- ==========================================
  gift_inst : entity work.gift64_core
    port map(
      clk      => clk,
      rst_n    => rst_n,
      start    => gift_start,
      enc_dec  => enc_reg,
      key_in   => key_reg,
      data_in  => data_reg,
      data_out => gift_out,
      done     => gift_done
    );

  -- ==========================================
  -- 4. UART Transmitter Instantiation
  -- ==========================================
  uart_tx_inst : entity work.uart_tx
    port map(
      clk       => clk,
      rst_n     => rst_n,
      tx_start  => tx_start,
      tx_data   => tx_data,
      tx_active => tx_active,
      tx_serial => uart_tx,
      tx_done   => tx_done
    );

  -- ==========================================
  -- 5. Transmit State Machine
  -- ==========================================
  process(clk, rst_n)
  begin
    if rst_n = '0' then
      tx_state    <= TX_IDLE;
      tx_start    <= '0';
      tx_byte_cnt <= 0;
      shift_out   <= (others => '0');
      
    elsif rising_edge(clk) then
      tx_start <= '0'; 
      
      case tx_state is
        when TX_IDLE =>
          if gift_done = '1' then
            shift_out   <= gift_out; 
            tx_byte_cnt <= 0;
            tx_state    <= TX_SEND_BYTE;
          end if;

        when TX_SEND_BYTE =>
          if tx_byte_cnt < 8 then
            tx_data  <= shift_out(63 downto 56);
            tx_start <= '1';
            tx_state <= TX_WAIT;
          else
            tx_state <= TX_IDLE;
          end if;

        when TX_WAIT =>
          if tx_done = '1' then
            shift_out   <= shift_out(55 downto 0) & x"00";
            tx_byte_cnt <= tx_byte_cnt + 1;
            tx_state    <= TX_SEND_BYTE;
          end if;

      end case;
    end if;
  end process;

end architecture;

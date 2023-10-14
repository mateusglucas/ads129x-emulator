-- Component that emulates the behavior of a daisy-chained ADS129x 
-- association in continuous conversion mode.
--
-- There is no support for SPI commands, so the DIN pin is omitted. To 
-- start/stop an acquisition, the START pin should be used.
--
-- To simplify the design, the nCS pin is omitted. The component behaves 
-- as it is always selected (nCS=0). 
--
-- The ERR output signal is an auxiliary pin to indicate reception
-- errors. 
-- When on high state, it indicates that the number of SCLK cycles in
-- the last frame before the current one was different than the expected
-- (9*24*N cycles). The ERR pin state is always relative to the last 
-- frame before the current one, being resetted on every new frame.
-- 
-- The number N of daisy-chained ADS129x is only relevant for the 
-- correct functioning of the ERR pin.
--
-- The bytes transferred on DOUT follow a counting up sequence (0x00, 
-- 0x01, 0x02, ... , 0xFF, ..., 0x00, 0x01, ...). The counting is
-- restarted at every new sampling period.

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY ads129x IS
	GENERIC
	(
		N	    : NATURAL:=8;   -- number of daisy-chained ADS129x
		DR	    : NATURAL:=4000 -- sampling rate, in samples/s
	);
	PORT
	(
		START	: IN STD_LOGIC;
		DOUT	: OUT STD_LOGIC:='0';   -- SPI MISO
		SCLK	: IN STD_LOGIC;         -- SPI CLK
		CLK		: IN STD_LOGIC;         -- 2.048 MHz clock
		ERR		: OUT STD_LOGIC:='0';   -- overrun
		nDRDY	: OUT STD_LOGIC         -- data ready
	);

END ads129x;

ARCHITECTURE behavioral OF ads129x IS

-- * fclk = 2.048 MHz
-- * START should stay high for at least 2*tclk
-- * nDRDY rises together with START and stays high for a period
--   tsettle = (2^13*1000/DR+9)*tclk
-- * A nDRDY fall after tsettle indicates new data available.
-- * After this first fall, nDRDY falling edges occur at every sample 
--   period (tDR).
-- * After a nDRDY falling edge, the DOUT is updated at every SCLK
--   rising edge and the nDRDY goes high after the first SCLK falling 
--   edge.
-- * If there is no SCLK during a sampling period, nDRDY goes high 
--   4*tclk before the start of a new sample period and falls again to 
--   indicate new samples available.
-- * If all the available data isn't read until 4*tclk before the start
--   of a new sampling period, ERR stays high for next sampling period. 

SIGNAL bit_cnt: NATURAL RANGE 0 TO 7:=0;
SIGNAL byte_val: UNSIGNED(0 TO 7):=(OTHERS=>'0'); -- MSB-first
SIGNAL byte_cnt: NATURAL RANGE 0 TO 9*3*N:=0;
SIGNAL t_cnt: NATURAL RANGE 0 TO 2**13*1000/DR+9-1:=0;

TYPE state_type IS (IDLE, SETTLE, DATAREADY, DATAUPDATE);
SIGNAL state : state_type:=IDLE;

-- not DATAREADY state
SIGNAL not_DATAREADY: STD_LOGIC:='1'; 

-- DATAREADY to DATAUPDATE transition
SIGNAL DATAREADY_to_DATAUPDATE: STD_LOGIC:='0'; 

-- transition to DATAREADY state
SIGNAL to_DATAREADY: STD_LOGIC:='0'; 

-- occurence of the first SCLK falling edge when state=DATAREADY
SIGNAL sclk_falling_edge: STD_LOGIC:='0'; 

BEGIN

nDRDY<='1' WHEN (state=SETTLE OR state=DATAUPDATE OR 
                 sclk_falling_edge='1') ELSE '0';
                 
not_DATAREADY<='0' WHEN (state=DATAREADY) ELSE '1';

-- state machine process
PROCESS(CLK,START)
BEGIN
	IF(START='0') THEN
		state<=IDLE;
		ERR<='0';
		t_cnt<=0;
		to_DATAREADY<='0';
		DATAREADY_to_DATAUPDATE<='0';
	ELSIF(RISING_EDGE(CLK)) THEN
		CASE state IS
		
			WHEN IDLE =>
				IF(START='1') THEN
					state<=SETTLE;
					t_cnt<=0;
				ELSE
					state<=IDLE;
				END IF;
				
			WHEN SETTLE=>
				IF(t_cnt=2**13*1000/DR+9-1) THEN
					state<=DATAREADY;
					to_DATAREADY<='1';
					t_cnt<=0;
				ELSE
					t_cnt<=t_cnt+1;
					state<=SETTLE;
				END IF;
				
			WHEN DATAREADY =>
				to_DATAREADY<='0';
				IF(t_cnt=2**11*1000/DR-1-4) THEN
					state<=DATAUPDATE;
					DATAREADY_to_DATAUPDATE<='1';
					IF(byte_cnt=9*3*N AND bit_cnt=0) THEN
						ERR<='0';
					ELSE
						ERR<='1';
					END IF;
					t_cnt<=0;
				ELSE
					state<=DATAREADY;
					t_cnt<=t_cnt+1;
				END IF;
				
			WHEN DATAUPDATE =>
				DATAREADY_to_DATAUPDATE<='0';
				IF(t_cnt=4-1) THEN
					state<=DATAREADY;
					to_DATAREADY<='1';
					t_cnt<=0;
					
				ELSE
					state<=DATAUPDATE;
					t_cnt<=t_cnt+1;
				END IF;
		END CASE;
	END IF;
END PROCESS;

-- DOUT process
PROCESS(SCLK, not_DATAREADY)
BEGIN
	IF(not_DATAREADY='1') THEN
		byte_cnt<=0;
		bit_cnt<=0;
		DOUT<='0';
	ELSIF(RISING_EDGE(SCLK)) THEN
		DOUT<=byte_val(bit_cnt);
		IF(bit_cnt=7) THEN
			byte_val<=byte_val+1;
			byte_cnt<=byte_cnt+1;
			bit_cnt<=0;
		ELSE
			bit_cnt<=bit_cnt+1;
		END IF;
	END IF;
END PROCESS;

-- process to set nDRDY high after the first SCLK falling edge
PROCESS(SCLK, not_DATAREADY)
BEGIN
	IF(not_DATAREADY='1') THEN
		sclk_falling_edge<='0';
	ELSIF(FALLING_EDGE(SCLK)) THEN	
		sclk_falling_edge<='1';
	END IF;
END PROCESS;
END behavioral;

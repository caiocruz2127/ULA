-- =============================================================================
-- ENTITY DEBOUNCE MODIFIED TO ACTIVE RESET HIGH
-- =============================================================================
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity debounce is
generic (
    CLOCK_FREQ_MHZ : integer := 50;
    DEBOUNCE_TIME_MS : integer := 20;
    RESET_ACTIVE_LOW : boolean := false;  -- CHANGED TO FALSE (active high)
    INPUT_ACTIVE_LOW : boolean := false
);
port (
    clk : in std_logic;
    reset : in std_logic;
    button_in : in std_logic;
    button_out : out std_logic;
    rising_pulse : out std_logic;
    falling_pulse : out std_logic
);
end entity debounce;

architecture rtl of debounce is
    function is_reset_active(signal rst : std_logic) return boolean is 
    begin
        if RESET_ACTIVE_LOW then
            return rst = '0';
        else
            return rst = '1';  -- Active reset high
        end if;
    end function;

    function normalize_input(signal inp : std_logic) return std_logic is
    begin
        if INPUT_ACTIVE_LOW then
            return not inp;
        else
            return inp;
        end if;
    end function;

    constant COUNTER_MAX : integer := (CLOCK_FREQ_MHZ * 1000) * DEBOUNCE_TIME_MS - 1;
    subtype counter_type is integer range 0 to COUNTER_MAX;

    signal counter : counter_type := 0;
    signal sync_ff : std_logic_vector(2 downto 0) := (others => '0');
    signal button_clean : std_logic := '0';
    signal button_prev : std_logic := '0';
    signal reset_n : std_logic;
    signal button_norm : std_logic;
begin
    reset_n <= '0' when is_reset_active(reset) else '1';
    button_norm <= normalize_input(button_in);

    sync_process: process(clk, reset_n)
    begin
        if reset_n = '0' then
            sync_ff <= (others => '0');
        elsif rising_edge(clk) then
            sync_ff <= sync_ff(1 downto 0) & button_norm;
        end if;
    end process sync_process;

    debounce_process: process(clk, reset_n)
    begin
        if reset_n = '0' then
            counter <= 0;
            button_clean <= '0';
            button_prev <= '0';
        elsif rising_edge(clk) then
            button_prev <= button_clean;

            if sync_ff(2) /= sync_ff(1) then
                counter <= 0;
            else
                if counter < COUNTER_MAX then
                    counter <= counter + 1;
                else
                    button_clean <= sync_ff(2);
                end if;
            end if;
        end if;
    end process debounce_process;

    button_out <= button_clean;
    rising_pulse <= button_clean and not button_prev;
    falling_pulse <= not button_clean and button_prev;
end architecture rtl;

-- =============================================================================
-- ENTITY ULA2
-- =============================================================================
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ula2 is
port (
    A, B : in signed(3 downto 0);
    Answer : out std_logic_vector(3 downto 0);
    Operations : in std_logic_vector(2 downto 0);
    Zero, Negative, Carry, Over : out std_logic
);
end ula2;

architecture hardware of ula2 is
    signal Operations_temp : std_logic_vector(3 downto 0);
begin
    process(A, B, Operations)
        variable temp : signed(4 downto 0); 
        variable mult_result : signed(7 downto 0);
    begin
        Carry <= '0';
        Over <= '0';

        case operations is
            when "000" => -- addition
                temp := resize(A, 5) + resize(B, 5);
                operations_temp <= std_logic_vector(temp(3 downto 0));
                Carry <= temp(4);
                Over <= (A(3) and B(3) and not temp(3)) or
                       (not A(3) and not B(3) and temp(3));

            when "001" => -- subtraction (A - B)
                temp := resize(A, 5) - resize(B, 5);
                operations_temp <= std_logic_vector(temp(3 downto 0));
                Carry <= not temp(4);
                Over <= (not A(3) and B(3) and temp(3)) or
                       (A(3) and not B(3) and not temp(3));

            when "010" => -- AND
                Operations_temp <= std_logic_vector(A) and std_logic_vector(B);

            when "011" => -- OR
                Operations_temp <= std_logic_vector(A) or std_logic_vector(B);

            when "100" => -- XOR
                Operations_temp <= std_logic_vector(A) xor std_logic_vector(B);

            when "101" => -- NOT A
                Operations_temp <= not std_logic_vector(A);

            when "110" => -- multiplication
                mult_result := A * B;
                Operations_temp <= std_logic_vector(mult_result(3 downto 0));
                
                if mult_result > 7 or mult_result < -8 then
                    Over <= '1';
                    Carry <= '1';
                else
                    Over <= '0';
                    Carry <= '0';
                end if;

            when "111" => -- shift left logic A
                temp := resize(A, 5);
                temp := temp sll 1;
                Operations_temp <= std_logic_vector(temp(3 downto 0));
                
                Carry <= A(3);
                Over <= A(3) xor temp(3);

            when others =>
                Operations_temp <= "0000";
                Carry <= '0';
                Over <= '0';
        end case;
    end process;

    Answer <= Operations_temp;
    Zero <= '1' when Operations_temp = "0000" else '0';
    Negative <= Operations_temp(3);
end hardware;

-- =============================================================================
-- TOP_LEVEL
-- =============================================================================
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity top_level is
port(
    CLOCK_50 : in std_logic;
    RESET_N : in std_logic;  -- Active reset HIGH (when pressed = '1')
    KEY0 : in std_logic;     -- confirmation button
    KEY1 : in std_logic;     -- go back button
    SW : in std_logic_vector(3 downto 0);
    LEDG : out std_logic_vector(3 downto 0);
    LEDR : out std_logic_vector(7 downto 0)
);
end top_level;

architecture rtl of top_level is
    -- Declaration of componentd
    component debounce is
    generic (
        CLOCK_FREQ_MHZ : integer := 50;
        DEBOUNCE_TIME_MS : integer := 20;
        RESET_ACTIVE_LOW : boolean := false;
        INPUT_ACTIVE_LOW : boolean := false
    );
    port (
        clk : in std_logic;
        reset : in std_logic;
        button_in : in std_logic;
        button_out : out std_logic;
        rising_pulse : out std_logic;
        falling_pulse : out std_logic
    );
    end component;

    component ula2 is
    port (
        A, B : in signed(3 downto 0);
        Answer : out std_logic_vector(3 downto 0);
        Operations : in std_logic_vector(2 downto 0);
        Zero, Negative, Carry, Over : out std_logic
    );
    end component;

    -- Internal signals
    signal reset_internal : std_logic;
    signal btn0_pulse, btn1_pulse : std_logic;

    -- States of the entry machine
    type input_state_type is (INPUT_OP, INPUT_A, INPUT_B, SHOW_RESULT);
    signal input_state : input_state_type;

    -- Internal registrars
    signal operacao_reg : std_logic_vector(2 downto 0) := "000";
    signal operando_a_reg : std_logic_vector(3 downto 0) := "0000";
    signal operando_b_reg : std_logic_vector(3 downto 0) := "0000";
    signal resultado : std_logic_vector(3 downto 0);

    -- ULA flags
    signal flag_zero, flag_negative, flag_carry, flag_overflow : std_logic;

begin
    -- Reset active high: when RESET_N =‘1’, system reset
    reset_internal <= RESET_N;

    -- Debounce instances
    debounce_key0: debounce
    generic map (
        CLOCK_FREQ_MHZ => 50,
        DEBOUNCE_TIME_MS => 20,
        RESET_ACTIVE_LOW => false,
        INPUT_ACTIVE_LOW => true
    )
    port map (
        clk => CLOCK_50,
        reset => reset_internal,
        button_in => KEY0,
        button_out => open,
        rising_pulse => btn0_pulse,
        falling_pulse => open
    );

    debounce_key1: debounce
    generic map (
        CLOCK_FREQ_MHZ => 50,
        DEBOUNCE_TIME_MS => 20,
        RESET_ACTIVE_LOW => false,
        INPUT_ACTIVE_LOW => true
    )
    port map (
        clk => CLOCK_50,
        reset => reset_internal,
        button_in => KEY1,
        button_out => open,
        rising_pulse => btn1_pulse,
        falling_pulse => open
    );

    -- Solo process: full states machine
state_machine: process(CLOCK_50)
begin
    if rising_edge(CLOCK_50) then
        if reset_internal = '1' then
            -- During the reset: always force the initial state
            input_state <= INPUT_OP;
            operacao_reg <= "000";
            operando_a_reg <= "0000";
            operando_b_reg <= "0000";

        else
            case input_state is
                when INPUT_OP =>
                    if btn0_pulse = '1' then
                        operacao_reg <= SW(2 downto 0);
                        input_state <= INPUT_A;
                    end if;

                when INPUT_A =>
                    if btn0_pulse = '1' then
                        operando_a_reg <= SW;
                        input_state <= INPUT_B;
                    elsif btn1_pulse = '1' then
                        input_state <= INPUT_OP;
                    end if;

                when INPUT_B =>
                    if btn0_pulse = '1' then
                        operando_b_reg <= SW;
                        input_state <= SHOW_RESULT;
                    elsif btn1_pulse = '1' then
                        input_state <= INPUT_A;
                    end if;

                when SHOW_RESULT =>
                    if btn1_pulse = '1' then
                        input_state <= INPUT_OP;
                    end if;

                when others =>
                    input_state <= INPUT_OP;
            end case;
        end if;
    end if;
end process;

    -- ULA instance
    ula_inst: ula2
    port map (
        A => signed(operando_a_reg),
        B => signed(operando_b_reg),
        Operations => operacao_reg,
        Answer => resultado,
        Zero => flag_zero,
        Negative => flag_negative,
        Carry => flag_carry,
        Over => flag_overflow
    );

    -- OUT
    LEDG <= resultado;

    -- State LEDs - INDICATION OF THE CURRENT STATE
    LEDR(7) <= '1' when input_state = SHOW_RESULT else '0';
    LEDR(6) <= '1' when input_state = INPUT_B else '0';
    LEDR(5) <= '1' when input_state = INPUT_A else '0';
    LEDR(4) <= '1' when input_state = INPUT_OP else '0';
    
    -- ULA FLAGS
    LEDR(3) <= flag_overflow;
    LEDR(2) <= flag_carry;
    LEDR(1) <= flag_negative;
    LEDR(0) <= flag_zero;

end architecture rtl;
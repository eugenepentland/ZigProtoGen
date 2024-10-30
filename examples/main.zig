pub const cmd_rotate_servo = struct {
    pub const id: u8 = 10;

    pub const request = struct {
        angle: u8,
    };
};

pub const cmd_goto_usb_bootloader = struct {
    pub const id: u8 = 125;
};

pub const cmd_set_led_level = struct {
    pub const id: u8 = 101;

    pub const request = struct {
        level: u8,
    };
};
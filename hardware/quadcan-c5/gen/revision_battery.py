"""Rev 1.1 battery power path. Pin numbers checked against manufacturer datasheets.

Design target only: protected 1S 4.2 V Li-ion pack, >=500 mAh, >=2 A discharge,
103AT-2-compatible pack-mounted 10k NTC. No LiFePO4 substitution.
"""
def revise(parts, P, R, C):
    removed = {'C9', 'D6', 'R7'}
    parts[:] = [p for p in parts if p['ref'] not in removed]
    d = {p['ref']: p for p in parts}
    # The old +5V buck output becomes VEH_5V. +5V now comes only from the boost.
    for ref in ('L1', 'C5', 'C6', 'R5'):
        d[ref]['pins'] = {k: ('VEH_5V' if v == '+5V' else v) for k,v in d[ref]['pins'].items()}
    # Diode OR keeps vehicle buck and USB isolated. USB power is optional via JP9.
    d['D4']['pins'] = {'1':'CHG_IN','2':'USB_PWR'}
    d['D5']['pins'] = {'1':'CHG_IN','2':'VEH_5V'}
    d['D4']['note'] = 'USB bench supply only through JP9; use a rated 5V source, not an unnegotiated host port'
    d['D5']['note'] = 'Vehicle/USB input OR; battery cannot backfeed either input'
    d['U2']['pins']['1'] = '+5V'
    d['C10']['pins']['1'] = '+5V'
    # Gate-combine interrupts; neither controller can fight the other at reset.
    d['U9']['pins']['4'] = 'CAN3_INT_N'
    d['U10']['pins']['4'] = 'CAN4_INT_N'
    d['R53']['pins']['2'] = 'CAN3_INT_N'
    # GPS RX moves off boot strap; boot strap becomes isolated UART output.
    d['U3']['pins'].update({'18':'GPS_TX_STRAP','21':'CAN34_INT','27':'ESP_GPS_RX'})
    d['U3']['note'] = 'GPIO23 MCP IRQ; GPIO26 GPS RX; GPIO27 GPS TX via disabled-at-reset buffer'
    d['R81']['pins']['1'] = 'GPS_TX_BUFFERED'
    for ref in ('U9','U10'):
        d[ref]['note'] = 'INT isolated by AND gate; byte-write IOCON; STB through XSTBY'
    add = parts.append
    s6='Package_TO_SOT_SMD:SOT-23-6'
    s5='Package_TO_SOT_SMD:SOT-23-5'
    c8='Capacitor_SMD:C_0805_2012Metric'
    c12='Capacitor_SMD:C_1210_3225Metric'
    add(P('JP9','Connector_Generic:Conn_01x02','Connector_PinHeader_2.54mm:PinHeader_1x02_P2.54mm_Vertical','USB_POWER','2.54mm jumper, default OPEN',{'1':'VBUS','2':'USB_PWR'},'battery','Fit only for a >=1A 5V bench supply; USB data works without jumper'))
    add(P('J7','Connector_Generic:Conn_01x03','Connector_JST:JST_PH_B3B-PH-K_1x03_P2.00mm_Vertical','BATTERY','JST B3B-PH-K-S',{'1':'BAT_PACK','2':'BAT_TS','3':'GND'},'battery','Verify pack polarity: 1 plus, 2 NTC, 3 minus; protected 1S Li-ion only'))
    add(P('F2','Device:Fuse','Fuse:Fuse_Littelfuse-NANO2-451_453','1.5A','Littelfuse 045301.5MR',{'1':'BAT_PACK','2':'BAT'},'battery'))
    add(P('U14','QuadCAN:BQ24074','QuadCAN:BQ24074_ThermalVia03','BQ24074','TI BQ24074RGTR',
          {'1':'BAT_TS','2':'BAT','3':'BAT','4':'GND','5':'CHG_IN','6':'GND','7':'PGOOD_N','8':'GND','9':'CHG_N','10':'VSYS','11':'VSYS','12':'CHG_ILIM','13':'CHG_IN','16':'CHG_ISET','17':'GND'},'battery',
          'ITERM/TMR intentionally open: default termination/timers; TS must reach actual pack NTC'))
    add(R('R90','8.87k','CHG_ISET','GND','battery',note='Nominal 100mA charge, worst KISET ~110mA'))
    add(R('R91','1.62k','CHG_ILIM','GND','battery',note='Nominal ~0.99A input limit; total board plus charging'))
    add(R('R92','100k','+3V3','PGOOD_N','battery'))
    add(R('R93','100k','+3V3','CHG_N','battery'))
    add(C('C90','4.7uF 10V','CHG_IN','GND','battery',c8))
    add(C('C91','10uF 10V','BAT','GND','battery',c8))
    add(C('C92','22uF 10V','VSYS','GND','battery',c12))
    add(P('U15','QuadCAN:TPS61023','Package_TO_SOT_SMD:SOT-563','TPS61023','TI TPS61023DRLR',
          {'1':'BOOST_FB','2':'BOOST_EN','3':'VSYS','4':'GND','5':'BOOST_SW','6':'+5V'},'battery','5V boost with true output disconnect; enables only above hardware UVLO'))
    add(P('L3','Device:L','Inductor_SMD:L_Bourns_SRP7028A_7.3x6.6mm','1uH','Bourns SRP7028A-1R0M',{'1':'VSYS','2':'BOOST_SW'},'battery','Verify saturation >= peak switch current over temperature'))
    add(R('R94','732k','+5V','BOOST_FB','battery'))
    add(R('R95','100k','BOOST_FB','GND','battery',note='0.595V reference: 4.950V nominal PWM output'))
    add(C('C93','10uF 10V','VSYS','GND','battery',c8))
    add(C('C94','22uF 10V','+5V','GND','battery',c12))
    add(C('C95','22uF 10V','+5V','GND','battery',c12))
    add(P('U16','QuadCAN:TLV3012B',s6,'TLV3012B','TI TLV3012BIDBVR',
          {'1':'BOOST_EN','2':'GND','3':'UVLO_SENSE','4':'UVLO_REF','5':'UVLO_REF','6':'VSYS'},'battery','Hardware hysteresis: ~3.16V off / ~3.66V restart, nominal; not pack protection'))
    add(R('R96','1M','VSYS','UVLO_SENSE','battery'))
    add(R('R97','560k','UVLO_SENSE','GND','battery'))
    add(R('R98','6.34M','BOOST_EN','UVLO_SENSE','battery'))
    add(R('R99','1M','BOOST_EN','GND','battery'))
    add(C('C96','100nF','VSYS','GND','battery'))
    add(C('C97','1nF','UVLO_REF','GND','battery'))
    # A second expander gives status inputs without consuming boot strap GPIOs.
    add(P('U17','Interface_Expansion:TCA9535PWR','Package_SO:TSSOP-24_4.4x7.8mm_P0.65mm','TCA9535 0x21','TI TCA9535PWR',
          {'2':'GND','3':'GND','21':'+3V3','22':'I2C_SCL','23':'I2C_SDA','24':'+3V3','12':'GND','4':'PGOOD_N','5':'CHG_N'},'battery','All pins input; unused inputs externally grounded'))
    for pin in ('6','7','8','9','10','11','13','14','15','16','17','18','19','20'): parts[-1]['pins'][pin]='GND'
    add(C('C98','100nF','+3V3','GND','battery'))
    add(P('U18','Analog_ADC:ADS1115IDGS','Package_SO:TSSOP-10_3x3mm_P0.5mm','ADS1115 0x48','TI ADS1115IDGSR',
          {'1':'GND','10':'I2C_SCL','9':'I2C_SDA','3':'GND','4':'BAT_ADC','5':'SYS_ADC','6':'GND','7':'GND','8':'+3V3'},'battery','AIN0 battery / AIN1 system, both divided by 4.03; ALERT unused'))
    add(C('C99','100nF','+3V3','GND','battery'))
    for top,bot,cap,rail,net in [('R100','R101','C100','BAT','BAT_ADC'),('R102','R103','C101','VSYS','SYS_ADC')]:
        add(R(top,'100k',rail,net,'battery')); add(R(bot,'33k',net,'GND','battery')); add(C(cap,'100nF',net,'GND','battery'))
    add(P('U19','74xGxx:74LVC1G08',s5,'74LVC1G08','TI SN74LVC1G08DBVR',{'1':'CAN3_INT_N','2':'CAN4_INT_N','3':'GND','4':'CAN34_INT','5':'+3V3'},'can3','Active-low interrupts combined without tying outputs together'))
    add(R('R104','10k','+3V3','CAN4_INT_N','can3'))
    add(C('C102','100nF','+3V3','GND','can3'))
    add(P('U20','74xGxx:74LVC1G125',s5,'74LVC1G125','TI SN74LVC1G125DBVR',{'1':'GPS_PWR_N','2':'GPS_TX_STRAP','3':'GND','4':'GPS_TX_BUFFERED','5':'+3V3'},'gps','OE high while GPS off; boot GPIO27 sees only buffer input'))
    add(R('R105','10k','+3V3','GPS_TX_STRAP','gps'))
    add(C('C103','100nF','+3V3','GND','gps'))

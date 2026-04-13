# hybrid_encryption
This encryption scheme uses both symmetric and asymmetric ciphers. The symmetric part is GIFT which is implemented in VHDL to run on an FPGA and asymmetric part ECDH in python which does the key generation and key exchange. The communication protocols used are UART(comm to fpga) and MQTT(between parties exchanging information).

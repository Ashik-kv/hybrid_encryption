import serial
import hashlib
import paho.mqtt.client as mqtt
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

# --- CONFIGURATION ---
SERIAL_PORT = "COM4" # port should be the one that is connected to fpga
BAUD_RATE   = 115200
MQTT_BROKER = "localhost" # make sure change the IP
MY_TOPIC    = "fpga/receiver/pubkey"
PEER_TOPIC  = "fpga/sender/pubkey"
DATA_TOPIC  = "fpga/secure/data"

# Global states
remote_public_key = None
session_key = None
user_data = {}

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[+] Receiver Connected to {MQTT_BROKER}")
        client.subscribe(PEER_TOPIC)
        client.subscribe(DATA_TOPIC)
        
        # NEW: Generate X25519 Private Key
        local_priv = x25519.X25519PrivateKey.generate()
        userdata['priv'] = local_priv
        
        # NEW: Serialize X25519 Public Key (Raw 32 bytes)
        pub_bytes = local_priv.public_key().public_bytes(
            encoding=serialization.Encoding.Raw,
            format=serialization.PublicFormat.Raw
        )
        client.publish(MY_TOPIC, pub_bytes.hex(), retain=False)
        print("[*] Published X25519 Public Key. Waiting for Sender...")
    else:
        print(f"[-] Connection failed. Code: {rc}")

def on_message(client, userdata, msg):
    global remote_public_key, session_key
    
    # CASE A: Received Sender's Public Key
    if msg.topic == PEER_TOPIC:
        try:
            pub_hex = msg.payload.decode().strip()
            # NEW: Load X25519 Public Key
            remote_public_key = x25519.X25519PublicKey.from_public_bytes(bytes.fromhex(pub_hex))
            
            # NEW: Perform X25519 Exchange
            shared_secret = userdata['priv'].exchange(remote_public_key)
            # Hash shared secret to 16 bytes for GIFT-64
            session_key = hashlib.sha256(shared_secret).digest()[:16]
            
            print("\n" + "="*45)
            print(f"RECEIVER SESSION KEY: {session_key.hex()}")
            print("="*45 + "\n")
        except Exception as e:
            print(f"[-] Key error: {e}")

    # CASE B: Received Encrypted Data
    elif msg.topic == DATA_TOPIC:
        if session_key:
            cipher_hex = msg.payload.decode().strip()
            print(f"[*] MQTT Ciphertext Received: {cipher_hex}")
            
            try:
                with serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2) as ser:
                    # Protocol: [Mode 0 (Decrypt)] + [Key (16)] + [Data (8)]
                    ser.write(bytes([0]) + session_key + bytes.fromhex(cipher_hex))
                    plaintext = ser.read(8)
                    if len(plaintext) == 8:
                        print(f"[SUCCESS] FPGA Decrypted: {plaintext.hex()}\n")
                    else:
                        print("[-] FPGA Timeout or partial read.")
            except Exception as e:
                print(f"[-] UART Error: {e}")
        else:
            print("[-] Received data, but session key not yet established.")

# --- START ---
client = mqtt.Client(userdata=user_data)
client.on_connect = on_connect
client.on_message = on_message
client.connect(MQTT_BROKER, 1883, 60)

print("[*] Receiver listening for handshake...")
client.loop_forever()

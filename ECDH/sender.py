import serial
import hashlib
import time
import paho.mqtt.client as mqtt
from cryptography.hazmat.primitives.asymmetric import x25519
from cryptography.hazmat.primitives import serialization

# --- CONFIGURATION ---
SERIAL_PORT = "COM4"  
BAUD_RATE   = 115200
MQTT_BROKER = "localhost" # <--- YOUR UBUNTU IP ADDRESS
MY_TOPIC    = "fpga/sender/pubkey"
PEER_TOPIC  = "fpga/receiver/pubkey"
DATA_TOPIC  = "fpga/secure/data"

# Global states
remote_public_key = None
# NEW: Generate X25519 Private Key
local_priv = x25519.X25519PrivateKey.generate()
session_key = None

def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[+] Connected to Mosquitto at {MQTT_BROKER}")
        client.subscribe(PEER_TOPIC)
        print(f"[*] Waiting for Receiver to announce its X25519 Key...")
    else:
        print(f"[-] Connection failed with code {rc}")

def on_message(client, userdata, msg):
    global remote_public_key
    if msg.topic == PEER_TOPIC:
        try:
            pub_hex = msg.payload.decode().strip()
            # NEW: Load X25519 Public Key from raw bytes
            remote_public_key = x25519.X25519PublicKey.from_public_bytes(bytes.fromhex(pub_hex))
            print("\n[!] ALERT: Receiver's X25519 Public Key received!")
        except Exception as e:
            print(f"[-] Key decoding error: {e}")

def communicate_with_fpga(mode, key, data):
    try:
        with serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2) as ser:
            packet = bytes([mode]) + key + data
            ser.write(packet)
            return ser.read(8)
    except Exception as e:
        print(f"[-] UART Error: {e}")
        return None

# --- EXECUTION FLOW ---
client = mqtt.Client()
client.on_connect = on_connect
client.on_message = on_message
client.connect(MQTT_BROKER, 1883, 60)
client.loop_start()

# 1. Wait for Receiver's Key
while remote_public_key is None:
    time.sleep(0.1)

# 2. Derive Session Key using X25519
print("[*] Performing X25519 Key Exchange...")
shared_secret = local_priv.exchange(remote_public_key)
# Still using SHA-256 to get a 16-byte key for your GIFT FPGA
session_key = hashlib.sha256(shared_secret).digest()[:16]

# 3. Publish Sender's Key BACK to Receiver
# NEW: X25519 uses Raw encoding (always 32 bytes)
pub_bytes = local_priv.public_key().public_bytes(
    encoding=serialization.Encoding.Raw,
    format=serialization.PublicFormat.Raw
)
client.publish(MY_TOPIC, pub_bytes.hex(), retain=False)
time.sleep(1)

print("\n" + "="*45)
print(f"X25519 SESSION KEY: {session_key.hex()}")
print("="*45 + "\n")

# 4. The Encryption & Publishing Loop
try:
    while True:
        data_hex = input("ENTER 16 HEX CHARS TO ENCRYPT: ").strip().lower()
        if len(data_hex) != 16:
            print("[-] Error: Need exactly 16 hex chars.")
            continue
        
        print("[*] Sending to FPGA via UART...")
        ciphertext = communicate_with_fpga(1, session_key, bytes.fromhex(data_hex))
        
        if ciphertext and len(ciphertext) == 8:
            print(f"[+] FPGA Encrypted Result: {ciphertext.hex()}")
            print(f"[*] Publishing Ciphertext to {DATA_TOPIC}...")
            client.publish(DATA_TOPIC, ciphertext.hex())
            print("[SUCCESS] Data sent to Receiver via Mosquitto.")
        else:
            print("[-] FPGA Error: No response or wrong length.")

except KeyboardInterrupt:
    print("\nExiting...")
finally:
    client.loop_stop()
import struct

class MyClass:
    def __init__(self, a: int, b: int, c: int):
        self.a = a
        self.b = b
        self.c = c
    
    def serialize(self) -> bytes:
        # Pack integers into a binary format
        # '<' indicates little-endian, 'B' is for unsigned char (1 byte)
        return struct.pack('<BBB', self.a, self.b, self.c)
    
    @classmethod
    def deserialize(cls, data: bytes):
        # Unpack binary data back into integers
        # Use 'B' to match the serialize method
        a, b, c = struct.unpack('<BBB', data)
        return cls(a, b, c)
    
test = MyClass(1, 2, 3)

# Serialize the object
serialized_data = test.serialize()
print("Serialized data:", serialized_data)

# Deserialize the data
deserialized_obj = MyClass.deserialize(serialized_data)
print("Deserialized object:", deserialized_obj)
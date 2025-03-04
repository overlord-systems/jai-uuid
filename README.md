# jai-uuid

This library provides generation, parsing, comparison, and string functions for UUIDs v4 and v7.

## Installation

This library imports [jai-sodium](https://github.com/overlord-systems/jai-sodium/), the Jai bindings for the libsodium cryptography library, to generate secure random numbers. Follow the jai-sodium installation instructions and ensure its in your import path (e.g. put jai-sodium in your modules folder).

Once you have jai-sodium, to install `jai-uuid`, simply put `Uuid.jai` in your modules folder.

## Usage

```c
#import "Basic";
#import "Uuid";

uuid_test :: () {

    // Uuid v4 test
    uuidv4_1 := uuid_v4();
    uuidv4_2 := uuid_v4();
    print("uuidv4_1 = %\n", tuuid_string(uuidv4_1));
    print("uuidv4_2 = %\n", tuuid_string(uuidv4_2));
    print("uuidv4_1 == uuidv4_1 = %\n", uuid_equal(uuidv4_1, uuidv4_1));
    print("uuidv4_2 == uuidv4_2 = %\n", uuid_equal(uuidv4_2, uuidv4_2));
    print("uuidv4_1 == uuidv4_2 = %\n", uuid_equal(uuidv4_1, uuidv4_2));

    // Uuid v7 test
    uuidv7_1 := uuid_v7();
    uuidv7_2 := uuid_v7();
    print("uuidv7_1 = %\n", tuuid_string(uuidv7_1));
    print("uuidv7_2 = %\n", tuuid_string(uuidv7_2));
    print("uuidv7_1 == uuidv7_1 = %\n", uuid_equal(uuidv7_1, uuidv7_1));
    print("uuidv7_2 == uuidv7_2 = %\n", uuid_equal(uuidv7_2, uuidv7_2));
    print("uuidv7_1 == uuidv7_2 = %\n", uuid_equal(uuidv7_1, uuidv7_2));
}
```

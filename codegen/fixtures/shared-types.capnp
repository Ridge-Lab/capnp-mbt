@0xf14fda62224bdd2b;

# Shared protocol vocabulary. These names are legal in Cap'n Proto and
# reserved as type declarations by the MoonBit compiler.
enum Int16 { none @0; ready @1; }
enum Int32 { none @0; ready @1; }
enum UInt32 { none @0; ready @1; }
enum V128 { none @0; ready @1; }
enum FuncRef { none @0; ready @1; }
enum BytesView { none @0; ready @1; }
enum StringView { none @0; ready @1; }
enum ReadOnlyArray { none @0; ready @1; }
const defaultState :Int32 = ready;

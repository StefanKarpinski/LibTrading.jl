# LibTrading

[![Build Status](https://travis-ci.org/StefanKarpinski/LibTrading.jl.svg)](https://travis-ci.org/StefanKarpinski/LibTrading.jl)

The Julia LibTrading package is a wrapper for the [libtrading library](https://github.com/libtrading/libtrading), which "is an open source API for high-performance, low-latency trading applications."

## Example Usage

After installing libtrading and running `make` to generate the dynamic shared library object – either named `libtrading.so` (UNIX) or `libtrading.dylib` (OS X), make sure that this library can be found by `dlopen` – for example, but changing directories to the libtrading top-level directory. In that top-level directory, run the `fix_server` example program with this command line:

```bash
$ tools/fix/fix_server -m 1 -p 7070
Server is listening to port 7070...
```

Install this package (using `Pkg.clone("LibTrading")`), and then try the following:

```julia
julia> using LibTrading

julia> session = FixSession(connect(7070))
FixSession(Ptr{Void} @0x00007faf53c03700,"fix-4.4","sender","target",TcpSocket(open, 0 bytes waiting),1,15)

julia> logon(session)

julia> req = FixMessage(
           FIX_MSG_TYPE_NEW_ORDER_SINGLE,
           TransactTime = "54191923311431120",
           ClOrdID = "ClOrdID",
           Symbol = "Symbol",
           OrderQty = 100,
           OrdType = "2",
           Side = "1",
           Price = 100
       )
FixMessage type 8 with 7 fields
 1: FixField(TransactTime: "54191923311431120")
 2: FixField(ClOrdID: "ClOrdID")
 3: FixField(Symbol: "Symbol")
 4: FixField(OrderQty: 100)
 5: FixField(OrdType: "2")
 6: FixField(Side: "1")
 7: FixField(Price: 100)

julia> send(session, req)

julia> res = recv(session)
FixMessage type 6 with 12 fields
 1: FixField(SenderCompID: "SELLSIDE")
 2: FixField(TargetCompID: "BUYSIDE")
 3: FixField(SendingTime: "20140505-22:15:25.356")
 4: FixField(OrderID: "OrderID")
 5: FixField(Symbol: "Symbol")
 6: FixField(ExecID: "ExecID")
 7: FixField(OrdStatus: "2")
 8: FixField(ExecType: "0")
 9: FixField(LeavesQty: 0.0)
 10: FixField(CumQty: 100.0)
 11: FixField(AvgPx: 100.0)
 12: FixField(Side: "1")

julia> logoff(session)
```

The `fix_server` test program should exit at this point.

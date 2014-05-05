module LibTrading

export
    FixSession,
        logon,
        logoff,
        test_request,
        time_update,
        send,
        recv,
    FixField,
    FixMessage,
        FIX_MSG_TYPE_HEARTBEAT,
        FIX_MSG_TYPE_TEST_REQUEST,
        FIX_MSG_TYPE_RESEND_REQUEST,
        FIX_MSG_TYPE_REJECT,
        FIX_MSG_TYPE_SEQUENCE_RESET,
        FIX_MSG_TYPE_LOGOUT,
        FIX_MSG_TYPE_EXECUTION_REPORT,
        FIX_MSG_TYPE_LOGON,
        FIX_MSG_TYPE_NEW_ORDER_SINGLE,
        FIX_MSG_TYPE_SNAPSHOT_REFRESH,
        FIX_MSG_TYPE_INCREMENT_REFRESH,
        FIX_MSG_TYPE_SESSION_STATUS,
        FIX_MSG_TYPE_SECURITY_STATUS,
        FIX_MSG_ORDER_CANCEL_REPLACE,
        FIX_MSG_ORDER_CANCEL_REJECT,
        FIX_MSG_TYPE_MAX,
        FIX_MSG_TYPE_UNKNOWN

import Base: TcpSocket, pointer, get!

const FIX_SOCKETS = TcpSocket[]

type FixSession
    pointer   :: Ptr{Void}
    dialect   :: ASCIIString
    sender    :: UTF8String
    target    :: UTF8String
    socket    :: TcpSocket
    fakefd    :: Cint
    heartbeat :: Int

    function FixSession(socket  :: TcpSocket;
                        dialect :: String = "fix-4.4",
                        sender  :: String = "sender",
                        target  :: String = "target",
                        heartbeat :: Real = 15)

        fd = findfirst(isopen, FIX_SOCKETS)
        if 0 < fd
            FIX_SOCKETS[fd] = socket
        else
            push!(FIX_SOCKETS, socket)
            fd = length(FIX_SOCKETS)
        end
        cfg = ccall((:fix_session_cfg_new, :libtrading),
            Ptr{Void}, (Ptr{Cchar}, Ptr{Cchar}, Cint, Ptr{Cchar}, Cint),
            utf8(sender), utf8(target), iround(heartbeat), ascii(dialect), fd)
        ptr = ccall((:fix_session_new, :libtrading), Ptr{Void}, (Ptr{Void},), cfg)
        fix = new(ptr, dialect, sender, target, socket, fd, heartbeat)
        finalizer(fix, fix->close(fix.socket))
        return fix
    end
end

#= define and install I/O hooks =#

immutable IOVec
    base::Ptr{Uint8}
    len::Csize_t
end

isdefined(Base, :read!) || const read! = read

function io_recv(fd::Cint, buf::Ptr{Uint8}, n::Csize_t, flags::Cint)
    socket = FIX_SOCKETS[fd]
    start_reading(socket)
    Base.wait_readnb(socket, 1)
    n = min(n, nb_available(socket.buffer))
    read!(socket.buffer, buf, n)
    return convert(Cssize_t, n)::Cssize_t
end

function io_sendmsg(fd::Cint, iovs::Ptr{IOVec}, n::Csize_t, flags::Cint)
    socket = FIX_SOCKETS[fd]
    len = 0
    for i = 1:n
        iov = unsafe_load(iovs, i)
        write(socket, iov.base, iov.len)
        len += iov.len
    end
    return convert(Cssize_t, len)::Cssize_t
end

unsafe_store!(
    convert(Ptr{Ptr{Void}}, cglobal((:io_recv, :libtrading))),
    cfunction(io_recv, Cssize_t, (Cint, Ptr{Uint8}, Csize_t, Cint))
)
unsafe_store!(
    convert(Ptr{Ptr{Void}}, cglobal((:io_sendmsg, :libtrading))),
    cfunction(io_sendmsg, Cssize_t, (Cint, Ptr{IOVec}, Csize_t, Cint))
)

#= fix field tags =#

const FIX_FIELD_TAGS = (Symbol=>Cint)[
    :Account                => 1,
    :AvgPx                  => 6,
    :BeginSeqNo             => 7,
    :BeginString            => 8,
    :BodyLength             => 9,
    :CheckSum               => 10,
    :ClOrdID                => 11,
    :CumQty                 => 14,
    :EndSeqNo               => 16,
    :ExecID                 => 17,
    :MsgSeqNum              => 34,
    :MsgType                => 35,
    :NewSeqNo               => 36,
    :OrderID                => 37,
    :OrderQty               => 38,
    :OrdStatus              => 39,
    :OrdType                => 40,
    :OrigClOrdID            => 41,
    :PossDupFlag            => 43,
    :Price                  => 44,
    :RefSeqNum              => 45,
    :SecurityID             => 48,
    :SenderCompID           => 49,
    :SendingTime            => 52,
    :Side                   => 54,
    :Symbol                 => 55,
    :TargetCompID           => 56,
    :Text                   => 58,
    :TransactTime           => 60,
    :RptSeq                 => 83,
    :EncryptMethod          => 98,
    :HeartBtInt             => 108,
    :TestReqID              => 112,
    :GapFillFlag            => 123,
    :ResetSeqNumFlag        => 141,
    :ExecType               => 150,
    :LeavesQty              => 151,
    :MDEntryType            => 269,
    :MDEntryPx              => 270,
    :MDEntrySize            => 271,
    :MDUpdateAction         => 279,
    :TradingSessionID       => 336,
    :LastMsgSeqNumProcessed => 369,
    :MDPriceLevel           => 1023,
]
const FIX_FIELD_TAGS_INV = [ v => k for (k,v) in FIX_FIELD_TAGS ]

fix_field_tag(sym::Symbol) = FIX_FIELD_TAGS[sym]
fix_field_tag(sym::String) = FIX_FIELD_TAGS[symbol(sym)]
fix_field_tag(num::Integer) = FIX_FIELD_TAGS_INV[convert(Cint,num)]

#= fix field types =#

const FIX_TYPE_INT       = 0
const FIX_TYPE_FLOAT     = 1
const FIX_TYPE_CHAR      = 2
const FIX_TYPE_STRING    = 3
const FIX_TYPE_CHECKSUM  = 4
const FIX_TYPE_MSGSEQNUM = 5

#= fix fields =#

immutable FixField # struct fix_field
    tag::Cint      # enum
    typ::Cint      # enum
    val::Int64     # union { int64_t, double, char, char* }
end

function FixField(sym::Union(Symbol,String), val::Char)
    isascii(val) || error("non-ASCII character: $(repr(val))")
    FixField(fix_field_tag(sym), FIX_TYPE_CHAR, hton(uint64(val)))
end

FixField(sym::Union(Symbol,String), val::Integer) =
    FixField(fix_field_tag(sym), FIX_TYPE_INT, val)
FixField(sym::Union(Symbol,String), val::Float64) =
    FixField(fix_field_tag(sym), FIX_TYPE_FLOAT, reinterpret(Int64,val))
FixField(sym::Union(Symbol,String), val::FloatingPoint) =
    FixField(sym, float64(val))

const FIX_FIELD_STRINGS = Dict{UTF8String,UTF8String}()

if !applicable(pointer,"string")
    pointer(s::ByteString) = pointer(s.data)
end
if !applicable(get!,Dict(),"key","default")
    get!(d::Dict, v, k) = haskey(d,k) ? d[k] : (d[k] = v)
end

function FixField(sym::Union(Symbol,String), val::String)
    val = get!(FIX_FIELD_STRINGS, val, val) # transcode, pin, canonicalize
    FixField(fix_field_tag(sym), FIX_TYPE_STRING, reinterpret(Int64, pointer(val)))
end

function fix_field_value(fld::FixField)
    fld.typ == FIX_TYPE_INT       && return fld.val
    fld.typ == FIX_TYPE_FLOAT     && return reinterpret(Float64, fld.val)
    fld.typ == FIX_TYPE_CHAR      && return char(ntoh(fld.val))
    fld.typ == FIX_TYPE_CHECKSUM  && return uint(fld.val)
    fld.typ == FIX_TYPE_MSGSEQNUM && return uint(fld.val)
    fld.typ == FIX_TYPE_STRING    || error("unknown FIX field type: $(fld.typ)")
    p = q = reinterpret(Ptr{Uint8}, fld.val)
    while unsafe_load(q) > 1; q += 1; end
    str = ccall(:jl_pchar_to_string, ByteString, (Ptr{Uint8}, Int), p, q-p)
    get!(FIX_FIELD_STRINGS, str, str)
end

function Base.show(io::IO, fld::FixField)
    print(io, "FixField(", fix_field_tag(fld.tag), ": ", repr(fix_field_value(fld)), ")")
end

#= fix message types =#

const FIX_MSG_TYPE_HEARTBEAT         = 0
const FIX_MSG_TYPE_TEST_REQUEST      = 1
const FIX_MSG_TYPE_RESEND_REQUEST    = 2
const FIX_MSG_TYPE_REJECT            = 3
const FIX_MSG_TYPE_SEQUENCE_RESET    = 4
const FIX_MSG_TYPE_LOGOUT            = 5
const FIX_MSG_TYPE_EXECUTION_REPORT  = 6
const FIX_MSG_TYPE_LOGON             = 7
const FIX_MSG_TYPE_NEW_ORDER_SINGLE  = 8
const FIX_MSG_TYPE_SNAPSHOT_REFRESH  = 9
const FIX_MSG_TYPE_INCREMENT_REFRESH = 10
const FIX_MSG_TYPE_SESSION_STATUS    = 11
const FIX_MSG_TYPE_SECURITY_STATUS   = 12
const FIX_MSG_ORDER_CANCEL_REPLACE   = 13
const FIX_MSG_ORDER_CANCEL_REJECT    = 14
const FIX_MSG_TYPE_MAX               = 15
const FIX_MSG_TYPE_UNKNOWN           = -1

#= fix messages =#

type FixMessage #<: Associative{Symbol,FixField}
    pointer::Ptr{Cint}

    function FixMessage(typ::Integer; kws...)
        msg = new(ccall((:fix_message_new, :libtrading), Ptr{Cint}, ()))
        unsafe_store!(msg.pointer, typ)
        finalizer(msg, fix_message_free)
        for (k,v) in kws
            push!(msg, FixField(k,v))
        end
        return msg
    end
    FixMessage(p::Ptr) = new(p)
end

function fix_message_free(msg::FixMessage)
    ccall((:fix_message_free, :libtrading), Void, (Ptr{Void},), msg.pointer)
end

fix_message_type(msg::FixMessage) = unsafe_load(msg.pointer)

#= manipilating fix messages =#

function Base.push!(msg::FixMessage, field::FixField)
    ccall((:fix_message_add_field, :libtrading), Void, (Ptr{Void}, Ptr{FixField}), msg.pointer, &field)
end

function Base.length(msg::FixMessage)
    int(ccall((:fix_get_field_count, :libtrading), Cint, (Ptr{Void},), msg.pointer))
end

function Base.getindex(msg::FixMessage, i::Integer)
    1 <= i <= length(msg) || error("invalid field index: $i")
    p = ccall((:fix_get_field_at, :libtrading), Ptr{FixField}, (Ptr{Void}, Cint), msg.pointer, i-1)
    unsafe_load(p)
end

function Base.show(io::IO, msg::FixMessage)
    n = length(msg)
    print(io, "FixMessage type $(fix_message_type(msg)) with $n fields")
    for i = 1:length(msg)
        print("\n $i: $(msg[i])")
    end
end

#= fix session API =#

function logon(session::FixSession)
    r = ccall((:fix_session_logon, :libtrading), Cint, (Ptr{Void},), session.pointer)
    r == 0 || error("fix_session_logon failed")
    return nothing
end

function logoff(session::FixSession)
    r = ccall((:fix_session_logout, :libtrading), Cint, (Ptr{Void}, Ptr{Uint8}), session.pointer, C_NULL)
    r == 0 || error("fix_session_logout failed")
    return nothing
end

function test_request(session::FixSession)
    r = ccall((:fix_session_test_request, :libtrading), Cint, (Ptr{Void},), session.pointer)
    r == 0 || error("fix_session_test_request failed")
    return nothing
end

function time_update(session::FixSession)
    r = ccall((:fix_session_time_update, :libtrading), Cint, (Ptr{Void},), session.pointer)
    r == 0 || error("fix_session_time_update failed")
    return nothing
end

function send(session::FixSession, msg::FixMessage, flags::Integer=zero(Cint))
    r = ccall((:fix_session_send, :libtrading), Cint, (Ptr{Void}, Ptr{Void}, Cint),
              session.pointer, msg.pointer, flags)
    r >= 0 || error("fix_message_send failed")
    return nothing
end

function recv(session::FixSession, flags::Integer=zero(Cint))
    p = ccall((:fix_session_recv, :libtrading), Ptr{Cint}, (Ptr{Void}, Cint),
              session.pointer, flags)
    p != C_NULL || error("no message received")
    return FixMessage(p)
end

end # module

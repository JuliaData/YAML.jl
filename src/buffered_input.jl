

# Simple buffered input that allows peeking an arbitrary number of characters
# ahead by maintaining a typically quite small buffer of a few characters.


mutable struct BufferedInput
    input::IO
    buffer::Vector{Char}
    offset::UInt64
    avail::UInt64

    function BufferedInput(input::IO)
        return new(input, Char[], 0, 0)
    end
end

# Read and buffer `n` more characters
function buffer!(bi::BufferedInput, n::Integer)::Nothing
    for i in (bi.offset + bi.avail) .+ (1:n)
        c = eof(bi.input) ? '\0' : read(bi.input, Char)
        if i ≤ length(bi.buffer)
            bi.buffer[i] = c
        else
            push!(bi.buffer, c)
        end
    end
    bi.avail += n
    nothing
end

# Peek the character in the i-th position relative to the current position.
# (0-based)
function peek(bi::BufferedInput, i::Integer=0)
    i1 = i + 1
    if bi.avail < i1
        buffer!(bi, i1 - bi.avail)
    end
    bi.buffer[bi.offset + i1]
end


# Return the string formed from the first n characters from the current position
# of the stream.
function prefix(bi::BufferedInput, n::Integer=1)::String
    bi.avail < n && buffer!(bi, n - bi.avail)
    String(bi.buffer[bi.offset .+ (1:n)])
end


# NOPE: This is wrong. What if n > bi.avail

# Advance the stream by n characters.
function forward!(bi::BufferedInput, n::Integer=1)
    if n < bi.avail
        bi.offset += n
        bi.avail -= n
    else
        n -= bi.avail
        bi.offset = 0
        bi.avail = 0
        while n > 0
            read(bi.input, Char)
            n -= 1
        end
    end
    nothing
end

# Ugly hack to allow peeking of `StringDecoder`s
function peek(io::StringDecoder, ::Type{UInt8})
    c = read(io, UInt8)
    io.skip -= 1
    c
end

# The same but for Julia 1.3
peek(io::StringDecoder) = peek(io, UInt8)

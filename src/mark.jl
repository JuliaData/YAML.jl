# Position within the document being parsed
struct Mark
    index::UInt64
    line::UInt64
    column::UInt64
end

function show(io::IO, mark::Mark)
    @printf(io, "line %d, column %d", mark.line, mark.column)
end

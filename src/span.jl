import Base:
    iterate, eltype, length, getindex,
    firstindex, lastindex, first, last

# Where in the stream a particular token lies.
struct Span
    start_mark::Mark
    end_mark::Mark
end

iterate(span::Span, i::Real=1) = i > 2 ? nothing : (getfield(span, i), i + 1)
eltype(span::Span) = Mark
length(span::Span) = 2
getindex(span::Span, i::Int) = getfield(span, i)
getindex(span::Span, i::Real) = getfield(span, convert(Int, i))
firstindex(span::Span) = 1
lastindex(span::Span) = 2
first(span::Span) = span.start_mark
last(span::Span) = span.end_mark

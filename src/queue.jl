type Queue{T}
    data::Vector{T}
    function Queue()
        new(Vector{T}())
    end
end

isempty(q::Queue) = length(q.data) == 0
length(q::Queue) = length(q.data)
peek(q::Queue) = q.data[1]
enqueue!{T}(q::Queue{T}, value::T) = push!(q.data, value)
# Enqueue into kth place.
enqueue!{T}(q::Queue{T}, value::T, k::Integer) = insert!(q.data, k+1, value)
dequeue!(q::Queue) = shift!(q.data)


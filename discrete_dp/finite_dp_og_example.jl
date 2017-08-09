struct SimpleOG{TI <: Integer, T <: Real,
                TR <: AbstractArray{T}, TQ <: AbstractArray{T}}
    B :: TI
    M :: TI
    alpha :: T
    beta :: T
    R :: TR
    Q :: TQ
end

function SimpleOG{T <: Real}(;B::Integer=10, M::Integer=5, alpha::T=0.5, beta::T=0.9)

    u(c) = c^alpha
    n = B + M + 1
    m = M + 1

    R = Matrix{T}(n, m)
    Q = zeros(Float64,n,m,n)

    for a in 0:M
        Q[:, a + 1, (a:(a + B)) + 1] = 1 / (B + 1)
        for s in 0:(B + M)
            R[s + 1, a + 1] = a<=s ? u(s - a) : -Inf
        end
    end

    return SimpleOG(B, M, alpha, beta, R, Q)
end

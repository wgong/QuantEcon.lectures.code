
#=

@author : Spencer Lyon <spencer.lyon@nyu.edu>

=#

using Distributions
using QuantEcon

# NOTE: only brute-force approach is available in bellman operator.
# Waiting on a simple constrained optimizer to be written in pure Julia

"""
A Jovanovic-type model of employment with on-the-job search.

The value function is given by

\\[V(x) = \\max_{\\phi, s} w(x, \\phi, s)\\]

for

    w(x, phi, s) := x(1 - phi - s) + beta (1 - pi(s)) V(G(x, phi)) +
                    beta pi(s) E V[ max(G(x, phi), U)

where

* `x`: human capital
* `s` : search effort
* `phi` : investment in human capital
* `pi(s)` : probability of new offer given search level s
* `x(1 - \phi - s)` : wage
* `G(x, \phi)` : new human capital when current job retained
* `U` : Random variable with distribution F -- new draw of human capital

##### Fields

- `A::Real` : Parameter in human capital transition function
- `alpha::Real` : Parameter in human capital transition function
- `bet::AbstractFloat` : Discount factor in (0, 1)
- `x_grid::AbstractVector` : Grid for potential levels of x
- `G::Function` : Transition `function` for human captial
- `pi_func::Function` : `function` mapping search effort to
   the probability of getting a new job offer
- `F::UnivariateDistribution` : A univariate distribution from which
   the value of new job offers is drawn
- `quad_nodes::Vector` : Quadrature nodes for integrating over phi
- `quad_weights::Vector` : Quadrature weights for integrating over phi
- `epsilon::AbstractFloat` : A small number, used in optimization routine

"""
struct JvWorker{TR <: Real, TF <: AbstractFloat, TUD <: UnivariateDistribution,
                TAV <: AbstractVector, TV <: Vector}
    A::TR
    alpha::TR
    bet::TF
    x_grid::TAV
    G::Function
    pi_func::Function
    F::TUD
    quad_nodes::TV
    quad_weights::TV
    epsilon::TF
end

"""
Constructor with default values for `JvWorker`

##### Arguments

 - `A::Real(1.4)` : Parameter in human capital transition function
 - `alpha::Real(0.6)` : Parameter in human capital transition function
 - `bet::Real(0.96)` : Discount factor in (0, 1)
 - `grid_size::Integer(50)` : Number of points in discrete grid for `x`
 - `epsilon::Float(1e-4)` : A small number, used in optimization routine

##### Notes

There is also a version of this function that accepts keyword arguments for
each parameter

"""
# use key word argument
function JvWorker(;A::Real=1.4, alpha::Real=0.6, bet::Real=0.96,
                  grid_size::Integer=50, epsilon::AbstractFloat=1e-4)
    G(x, phi) = A .* (x .* phi).^alpha
    pi_func = sqrt
    F = Beta(2, 2)

    # integration bounds
    a, b = quantile(F, 0.005), quantile(F, 0.995)

    # quadrature nodes/weights
    nodes, weights = qnwlege(21, a, b)

    # Set up grid over the state space for DP
    # Max of grid is the max of a large quantile value for F and the
    # fixed point y = G(y, 1).
    grid_max = max(A^(1.0 / (1.0 - alpha)), quantile(F, 1 - epsilon))

    # range for linspace(epsilon, grid_max, grid_size). Needed for
    # CoordInterpGrid below
    x_grid = linspace(epsilon, grid_max, grid_size)

    JvWorker(A, alpha, bet, x_grid, G, pi_func, F, nodes, weights, epsilon)
end


"""
Apply the Bellman operator for a given model and initial value,
returning only the value function

##### Arguments

- `jv::JvWorker` : Instance of `JvWorker`
- `V::Vector`: Current guess for the value function
- `new_V::Vector` : Storage for updated value function

##### Returns

None, `new_V` is updated in place with the value function.

##### Notes

Currently, only the brute-force approach is available.
We are waiting on a simple constrained optimizer to be written in pure Julia

"""
function bellman_operator!(jv::JvWorker, V::AbstractVector, new_V::AbstractVector)

    # simplify notation
    G, pi_func, F, bet, epsilon = jv.G, jv.pi_func, jv.F, jv.bet, jv.epsilon
    nodes, weights = jv.quad_nodes, jv.quad_weights

    # prepare interpoland of value function
    Vf = LinInterp(jv.x_grid, V)

    # instantiate the linesearch variables
    max_val = -1.0
    cur_val = 0.0
    max_s = 1.0
    max_phi = 1.0
    search_grid = linspace(epsilon, 1.0, 15)

    for (i, x) in enumerate(jv.x_grid)

        function w(z)
            s, phi = z
            h(u) = [Vf(max(G(x, phi), uval)) * pdf(F, uval) for uval in u]
            integral = do_quad(h, nodes, weights)
            q = pi_func(s) * integral + (1.0 - pi_func(s)) * Vf(G(x, phi))

            return - x * (1.0 - phi - s) - bet * q
        end

        for s in search_grid
            for phi in search_grid
                cur_val = ifelse(s + phi <= 1.0, -w((s, phi)), -1.0)
                if cur_val > max_val
                    max_val, max_s, max_phi = cur_val, s, phi
                end
            end
        end

        new_V[i] = max_val
    end
end

"""
Apply the Bellman operator for a given model and initial value, returning policies

##### Arguments

- `jv::JvWorker` : Instance of `JvWorker`
- `V::Vector`: Current guess for the value function
- `out::Tuple{Vector, Vector}` : Storage for the two policy rules

##### Returns

None, `out` is updated in place with the two policy functions.

##### Notes

Currently, only the brute-force approach is available.
We are waiting on a simple constrained optimizer to be written in pure Julia

"""
function bellman_operator!(jv::JvWorker, V::AbstractVector,
                           out::Tuple{AbstractVector, AbstractVector})

    # simplify notation
    G, pi_func, F, bet, epsilon = jv.G, jv.pi_func, jv.F, jv.bet, jv.epsilon
    nodes, weights = jv.quad_nodes, jv.quad_weights

    # prepare interpoland of value function
    Vf = LinInterp(jv.x_grid, V)

    # instantiate variables
    s_policy, phi_policy = out[1], out[2]

    # instantiate the linesearch variables
    max_val = -1.0
    cur_val = 0.0
    max_s = 1.0
    max_phi = 1.0
    search_grid = linspace(epsilon, 1.0, 15)

    for (i, x) in enumerate(jv.x_grid)

        function w(z)
            s, phi = z
            h(u) = [Vf(max(G(x, phi), uval)) * pdf(F, uval) for uval in u]
            integral = do_quad(h, nodes, weights)
            q = pi_func(s) * integral + (1.0 - pi_func(s)) * Vf(G(x, phi))

            return - x * (1.0 - phi - s) - bet * q
        end

        for s in search_grid
            for phi in search_grid
                cur_val = ifelse(s + phi <= 1.0, -w((s, phi)), -1.0)
                if cur_val > max_val
                    max_val, max_s, max_phi = cur_val, s, phi
                end
            end
        end

      s_policy[i], phi_policy[i] = max_s, max_phi
  end
end

function bellman_operator(jv::JvWorker, V::AbstractVector; ret_policies::Bool=false)
    out = ifelse(ret_policies, (similar(V), similar(V)), similar(V))
    bellman_operator!(jv, V, out)
    return out
end

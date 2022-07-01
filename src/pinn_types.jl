"""
???
"""
struct LogOptions
    log_frequency::Int64
    # TODO: add in an option for saving plots in the log. this is currently not done because the type of plot is dependent on the PDESystem
    #       possible solution: pass in a plot function?
    #       this is somewhat important because we want to support plotting adaptive weights that depend on pde independent variables
    #       and not just one weight for each loss function, i.e. pde_loss_weights(i, t, x) and since this would be function-internal,
    #       we'd want the plot & log to happen internally as well
    #       plots of the learned function can happen in the outer callback, but we might want to offer that here too

    SciMLBase.@add_kwonly function LogOptions(; log_frequency = 50)
        new(convert(Int64, log_frequency))
    end
end

"""This function is defined here as stubs to be overriden by the subpackage NeuralPDELogging if imported"""
function logvector(logger, v::AbstractVector{R}, name::AbstractString,
                   step::Integer) where {R <: Real}
    nothing
end

"""This function is defined here as stubs to be overriden by the subpackage NeuralPDELogging if imported"""
function logscalar(logger, s::R, name::AbstractString, step::Integer) where {R <: Real}
    nothing
end

"""
```julia
PhysicsInformedNN(chain,
                  strategy;
                  init_params = nothing,
                  phi = nothing,
                  param_estim = false,
                  additional_loss = nothing,
                  adaptive_loss = nothing,
                  logger = nothing,
                  log_options = LogOptions(),
                  iteration = nothing,
                  kwargs...) where {iip}

A `discretize` algorithm for the ModelingToolkit PDESystem interface which transforms a
`PDESystem` into an `OptimizationProblem` using the Physics-Informed Neural Networks (PINN)
methodology.

## Positional Arguments

* `chain`: a vector of Flux.jl or Lux.jl chains with a d-dimensional input and a
  1-dimensional output corresponding to each of the dependent variables. Note that this
  specification respects the order of the dependent variables as specified in the PDESystem.
* `strategy`: determines which training strategy will be used. See the Training Strategy
  documentation for more details.

## Keyword Arguments

* `init_params`: the initial parameters of the neural networks. This should match the
  specification of the chosen `chain` library. For example, if a Flux.chain is used, then
  `init_params` should match `Flux.destructure(chain)[1]` in shape. If `init_params` is not
  given, then the neural network default parameters are used.
* `phi`: a trial solution, specified as `phi(x,p)` where `x` is the coordinates vector for
  the dependent variable and `p` are the weights of the phi function (generally the weights
  of the neural network defining `phi`). By default this is generated from the `chain`. This
  should only be used to more directly impose functional information in the training problem,
  for example imposing the boundary condition by the test function formulation.
* `adaptive_loss`: the choice for the adaptive loss function. See the
  [adaptive loss page](@id adaptive_loss) for more details. Defaults to no adaptivity.
* `additional_loss`: a function `additional_loss(phi, θ, p_)` where `phi` are the neural
  network trial solutions, `θ` are the weights of the neural network(s), and `p_` are the
  hyperparameters of the `OptimizationProblem`. If `param_estim = true`, then `θ` additionally
  contains the parameters of the differential equation appended to the end of the vector.
* `param_estim`: whether the parameters of the differential equation should be included in
  the values sent to the `additional_loss` function. Defaults to `true`.
* `logger`: ?? needs docs
* `log_options`: ?? why is this separate from the logger?
* `iteration`: used to control the iteration counter???
* `kwargs`: Extra keyword arguments which are splatted to the `OptimizationProblem` on `solve`.
"""
struct PhysicsInformedNN{T, P, PH, DER, PE, AL, ADA, LOG, K} <: AbstractPINN
    strategy::T
    init_params::P
    phi::PH
    derivative::DER
    param_estim::PE
    additional_loss::AL
    adaptive_loss::ADA
    logger::LOG
    log_options::LogOptions
    iteration::Vector{Int64}
    self_increment::Bool
    multioutput::Bool
    kwargs::K

    @add_kwonly function PhysicsInformedNN(chain,
                                           strategy;
                                           init_params = nothing,
                                           phi = nothing,
                                           derivative = nothing,
                                           param_estim = false,
                                           additional_loss = nothing,
                                           adaptive_loss = nothing,
                                           logger = nothing,
                                           log_options = LogOptions(),
                                           iteration = nothing,
                                           kwargs...) where {iip}
        if init_params === nothing
            if chain isa AbstractArray
                initθ = DiffEqFlux.initial_params.(chain)
            else
                initθ = DiffEqFlux.initial_params(chain)
            end
        else
            initθ = init_params
        end

        multioutput = typeof(chain) <: AbstractArray

        type_initθ = multioutput ? Base.promote_typeof.(initθ)[1] :
                     Base.promote_typeof(initθ)

        if phi === nothing
            if multioutput
                _phi = Phi.(chain)
            else
                _phi = Phi(chain)
            end
        else
            _phi = phi
        end

        if derivative === nothing
            _derivative = numeric_derivative
        else
            _derivative = derivative
        end

        if !(typeof(adaptive_loss) <: AbstractAdaptiveLoss)
            floattype = eltype(initθ)
            if floattype <: Vector
                floattype = eltype(floattype)
            end
            adaptive_loss = NonAdaptiveLoss{floattype}()
        end

        if iteration isa Vector{Int64}
            self_increment = false
        else
            iteration = [1]
            self_increment = true
        end

        new{typeof(strategy), typeof(initθ), typeof(_phi), typeof(_derivative),
            typeof(param_estim),
            typeof(additional_loss), typeof(adaptive_loss), typeof(logger), typeof(kwargs)}(strategy,
                                                                                            initθ,
                                                                                            _phi,
                                                                                            _derivative,
                                                                                            param_estim,
                                                                                            additional_loss,
                                                                                            adaptive_loss,
                                                                                            logger,
                                                                                            log_options,
                                                                                            iteration,
                                                                                            self_increment,
                                                                                            multioutput,
                                                                                            kwargs)
    end
end

"""
PINNRepresentation

An internal reprsentation of a physics-informed neural network (PINN). This is the struct
used internally and returned for introspection by `symbolic_discretize`.

## Fields


"""
mutable struct PINNRepresentation
    """
    The equations of the PDE
    """
    eqs::Any
    """
    The boundary condition equations
    """
    bcs::Any
    """
    The domains for each of the independent variables
    """
    domains::Any
    """
    ???
    """
    eq_params::Any
    """
    ???
    """
    defaults::Any
    """
    ???
    """
    default_p::Any
    """
    Whether parameters are to be appended to the `additional_loss`
    """
    param_estim::Any
    """
    The `additional_loss` function as provided by the user
    """
    additional_loss::Any
    """
    The adaptive loss function
    """
    adaloss::Any
    """
    The dependent variables of the system
    """
    depvars::Any
    """
    The independent variables of the system
    """
    indvars::Any
    """
    A dictionary form of the independent variables. Define the structure ???
    """
    dict_indvars::Any
    """
    A dictionary form of the dependent variables. Define the structure ???
    """
    dict_depvars::Any
    """
    ???
    """
    dict_depvar_input::Any
    """
    The logger as provided by the user
    """
    logger::Any
    """
    Whether there are multiple outputs, i.e. a system of PDEs
    """
    multioutput::Bool
    """
    The iteration counter used inside of the cost function
    """
    iteration::Vector{Int}
    """
    The initial parameters as provided by the user. If the PDE is a system of PDEs, this
    will be an array of array of
    """
    initθ::Any
    """
    The initial parameters as a flattened array. This is the array that is used in the
    construction of the OptimizationProblem
    """
    flat_initθ::Any
    """
    The representation of the test function of the PDE solution
    """
    phi::Any
    """
    The function used for computing the derivative
    """
    derivative::Any
    """
    The training strategy as provided by the user
    """
    strategy::AbstractTrainingStrategy
    """
    ???
    """
    pde_indvars::Any
    """
    ???
    """
    bc_indvars::Any
    """
    ???
    """
    pde_integration_vars::Any
    """
    ???
    """
    bc_integration_vars::Any
    """
    ???
    """
    integral::Any
    """
    The PDE loss functions as represented in Julia AST
    """
    symbolic_pde_loss_functions::Any
    """
    The boundary condition loss functions as represented in Julia AST
    """
    symbolic_bc_loss_functions::Any
    """
    The PINNLossFunctions, i.e. the generated loss functions
    """
    loss_functions::Any
end

"""
PINNLossFunctions

The generated functions from the PINNRepresentation
"""
struct PINNLossFunctions
    """
    The boundary condition loss functions
    """
    bc_loss_functions::Any
    """
    The PDE loss functions
    """
    pde_loss_functions::Any
    """
    The full loss function, combining the PDE and boundary condition loss functions.
    This is the loss function that is used by the optimizer.
    """
    full_loss_function::Any
    """
    The wrapped `additional_loss`, as pieced together for the optimizer.
    """
    additional_loss_function::Any
    """
    The pre-data version of the PDE loss function
    """
    datafree_pde_loss_functions::Any
    """
    The pre-data version of the BC loss function
    """
    datafree_bc_loss_functions::Any
end

"""
An encoding of the test function phi that is used for calculating the PDE
value at domain points x

Fields:

- `f`: A representation of the chain function. If FastChain, then `f(x,p)`,
  if Chain then `f(p)(x)` (from Flux.destructure)
"""
struct Phi{C}
    f::C
    Phi(chain::FastChain) = new{typeof(chain)}(chain)
    Phi(chain::Flux.Chain) = (re = Flux.destructure(chain)[2]; new{typeof(re)}(re))
end

(f::Phi{<:FastChain})(x, θ) = f.f(adapt(parameterless_type(θ), x), θ)
(f::Phi{<:Optimisers.Restructure})(x, θ) = f.f(θ)(adapt(parameterless_type(θ), x))

function get_u()
    u = (cord, θ, phi) -> phi(cord, θ)
end

# the method to calculate the derivative
function numeric_derivative(phi, u, x, εs, order, θ)
    _epsilon = one(eltype(θ)) / cbrt(eps(eltype(θ)))
    ε = εs[order]
    ε = adapt(parameterless_type(θ), ε)
    x = adapt(parameterless_type(θ), x)

    # any(x->x!=εs[1],εs)
    # εs is the epsilon for each order, if they are all the same then we use a fancy formula
    # if order 1, this is trivially true

    if order > 4 || any(x -> x != εs[1], εs)
        return (numeric_derivative(phi, u, x .+ ε, @view(εs[1:(end - 1)]), order - 1, θ)
                .-
                numeric_derivative(phi, u, x .- ε, @view(εs[1:(end - 1)]), order - 1, θ)) .*
               _epsilon ./ 2
    elseif order == 4
        return (u(x .+ 2 .* ε, θ, phi) .- 4 .* u(x .+ ε, θ, phi)
                .+
                6 .* u(x, θ, phi)
                .-
                4 .* u(x .- ε, θ, phi) .+ u(x .- 2 .* ε, θ, phi)) .* _epsilon^4
    elseif order == 3
        return (u(x .+ 2 .* ε, θ, phi) .- 2 .* u(x .+ ε, θ, phi) .+ 2 .* u(x .- ε, θ, phi)
                -
                u(x .- 2 .* ε, θ, phi)) .* _epsilon^3 ./ 2
    elseif order == 2
        return (u(x .+ ε, θ, phi) .+ u(x .- ε, θ, phi) .- 2 .* u(x, θ, phi)) .* _epsilon^2
    elseif order == 1
        return (u(x .+ ε, θ, phi) .- u(x .- ε, θ, phi)) .* _epsilon ./ 2
    else
        error("This shouldn't happen!")
    end
end
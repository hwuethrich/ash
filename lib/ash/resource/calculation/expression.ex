defmodule Ash.Resource.Calculation.Expression do
  @moduledoc false
  use Ash.Calculation

  def expression(opts, context) do
    expr =
      Ash.Filter.build_filter_from_template(
        opts[:expr],
        context[:actor],
        context,
        context[:context] || %{}
      )

    if context[:ash][:type] do
      {:ok, expr} =
        Ash.Query.Function.Type.new([
          expr,
          context[:ash][:type],
          context[:ash][:constraints] || []
        ])

      expr
    else
      expr
    end
  end

  def calculate([], _, _), do: []

  def calculate([%resource{} | _] = records, opts, context) do
    expression =
      Ash.Filter.build_filter_from_template(opts[:expr], nil, context, context[:context] || %{})

    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, values} ->
      case Ash.Filter.hydrate_refs(expression, %{
             resource: resource,
             aggregates: %{},
             calculations: %{},
             public?: false
           }) do
        {:ok, expression} ->
          case Ash.Expr.eval_hydrated(expression,
                 record: record,
                 resource: resource,
                 unknown_on_unknown_refs?: true
               ) do
            {:ok, value} ->
              value = try_cast_stored(value, context[:ash][:type], context[:ash][:constraints])
              {:cont, {:ok, [value | values]}}

            :unknown ->
              {:halt, :unknown}

            {:error, error} ->
              {:halt, {:error, error}}
          end

        {:error, error} ->
          {:halt, {:error, error}}
      end
    end)
    |> case do
      {:ok, values} ->
        {:ok, Enum.reverse(values)}

      :unknown ->
        :unknown

      {:error, error} ->
        {:error, error}
    end
  end

  def try_cast_stored(value, nil, _constraints), do: value

  def try_cast_stored(value, type, constraints) do
    case Ash.Type.cast_stored(type, value, constraints || []) do
      {:ok, value} -> value
      _ -> value
    end
  end

  def load(query, opts, context) do
    expr =
      Ash.Filter.build_filter_from_template(opts[:expr], nil, context, context[:context] || %{})

    case Ash.Filter.hydrate_refs(expr, %{
           resource: query.resource,
           calculations: query.calculations,
           aggregates: query.aggregates,
           public?: false
         }) do
      {:ok, expression} ->
        expression
        |> Ash.Filter.used_aggregates()
        |> Enum.uniq()

      {:error, _} ->
        []
    end
  end

  def select(query, opts, context) do
    expr =
      Ash.Filter.build_filter_from_template(opts[:expr], nil, context, context[:context] || %{})

    case Ash.Filter.hydrate_refs(expr, %{
           resource: query.resource,
           calculations: query.calculations,
           aggregates: query.aggregates,
           public?: false
         }) do
      {:ok, expression} ->
        expression
        |> Ash.Filter.list_refs()
        |> Enum.filter(fn ref ->
          ref.relationship_path == [] && match?(%Ash.Resource.Attribute{}, ref.attribute)
        end)
        |> Enum.map(& &1.attribute.name)

      _ ->
        []
    end
  end
end

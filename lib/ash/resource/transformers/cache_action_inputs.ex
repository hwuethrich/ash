defmodule Ash.Resource.Transformers.CacheActionInputs do
  @moduledoc "Stores the set of valid input keys for each action"
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  def transform(dsl_state) do
    final_attributes_to_require =
      dsl_state
      |> Ash.Resource.Info.attributes()
      |> Enum.reject(&(&1.allow_nil? || &1.generated?))

    dsl_state =
      Transformer.persist(dsl_state, :attributes_to_require, final_attributes_to_require)

    dsl_state
    |> Ash.Resource.Info.actions()
    |> Enum.reject(&(&1.type in [:read, :action]))
    |> Enum.reduce(dsl_state, fn action, dsl_state ->
      inputs =
        action.arguments
        |> Enum.map(& &1.name)
        |> Enum.concat(action.accept)
        |> Enum.flat_map(&[&1, to_string(&1)])

      argument_names = action.arguments |> Enum.map(& &1.name)

      accepted =
        action.accept
        |> Kernel.++(action.require_attributes)
        |> Kernel.--(action.allow_nil_input)
        |> Kernel.--(argument_names)

      attributes_to_require_for_action =
        dsl_state
        |> Ash.Resource.Info.attributes()
        |> Enum.reject(
          &(&1.name not in accepted || !&1.writable? || &1.generated? ||
              (&1.allow_nil? && &1.name not in action.require_attributes))
        )

      inputs
      |> Enum.reduce(dsl_state, fn input, dsl_state ->
        Transformer.persist(dsl_state, {:action_inputs, action.name, input}, true)
      end)
      |> Transformer.persist({:action_inputs, action.name}, MapSet.new(inputs))
      |> Transformer.persist(
        {:attributes_to_require, action.name},
        attributes_to_require_for_action
      )
    end)
    |> then(&{:ok, &1})
  end
end

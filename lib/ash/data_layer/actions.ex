defmodule Ash.DataLayer.Actions do
  def run_create_action(resource, action, attributes, relationships, params) do
    case Ash.Data.create(resource, action, attributes, relationships, params) do
      {:ok, record} ->
        Ash.Data.side_load(record, Map.get(params, :include, []), resource)

      {:error, error} ->
        {:error, error}
    end
  end

  def run_update_action(%resource{} = record, action, attributes, relationships, params) do
    with {:ok, record} <- Ash.Data.update(record, action, attributes, relationships, params),
         {:ok, [record]} <- Ash.Data.side_load([record], Map.get(params, :include, []), resource) do
      {:ok, record}
    else
      {:error, error} -> {:error, error}
    end
  end

  def run_destroy_action(record, action, params) do
    Ash.Data.delete(record, action, params)
  end

  def run_read_action(resource, action, params) do
    auth_context = %{
      resource: resource,
      action: action,
      params: params
    }

    user = Map.get(params, :user)

    with {%{prediction: prediction} = instructions, per_check_data}
         when prediction != :unauthorized <-
           Ash.Authorization.Authorizer.authorize_precheck(user, action.rules, auth_context),
         params <- add_auth_side_loads(params, instructions),
         {:ok, query} <- Ash.Data.resource_to_query(resource),
         {:ok, filtered_query} <- Ash.Data.filter(resource, query, params),
         {:ok, paginator} <-
           Ash.DataLayer.Paginator.paginate(resource, action, filtered_query, params),
         {:ok, found} <- Ash.Data.get_many(paginator.query, resource),
         :allow <-
           Ash.Authorization.Authorizer.authorize(
             user,
             found,
             action.rules,
             auth_context,
             per_check_data
           ),
         {:ok, result} <- Ash.Data.side_load(found, Map.get(params, :include, []), resource) do
      {:ok, %{paginator | results: result}}
    else
      {%{prediction: :unauthorized}, _} ->
        # TODO: Nice errors here!
        {:error, :unauthorized}

      {:unauthorized, _data} ->
        # TODO: Nice errors here!
        {:error, :unauthorized}
    end
  end

  defp add_auth_side_loads(params, %{side_load: side_load}) do
    params
    |> Map.put_new(:side_load, [])
    |> Map.update!(:side_load, &deep_merge_side_loads(&1, side_load))
  end

  defp add_auth_side_loads(params, _), do: params

  defp deep_merge_side_loads(left, right) do
    left_sanitized = sanitize_side_load_part(left)
    right_sanitized = sanitize_side_load_part(right)

    Keyword.merge(left_sanitized, right_sanitized, fn _, v1, v2 ->
      deep_merge_side_loads(v1, v2)
    end)
  end

  defp sanitize_side_load_part(list) when is_list(list) do
    Enum.map(list, fn item ->
      case item do
        item when is_atom(item) ->
          {item, []}

        {k, v} ->
          {k, v}
      end
    end)
  end

  defp sanitize_side_load_part(item), do: [{item, []}]
end

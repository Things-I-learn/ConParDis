defmodule BoutiqueInventory do
  def new, do: []

  def add_item(nil, nil), do: []
  def add_item(nil, item), do: [item]
  def add_item(inventory, nil), do: inventory
  def add_item(inventory, item), do: [item | inventory]

  def add_size(nil, _item_name, _size, _quantity), do: []

  def add_size(inventory, item_name, size, quantity) do
    Enum.map(inventory, fn item ->
      if is_map(item) and Map.get(item, :name) == item_name do

        tallas =
          case Map.get(item, :quantity_by_size) do
            mapa when is_map(mapa) -> mapa
            _ -> %{}
          end

        nuevas_tallas =
          Map.put(tallas, size, quantity)

        Map.put(item, :quantity_by_size, nuevas_tallas)

      else
        item
      end
    end)
  end

  def remove_size(nil, _item_name, _size), do: []

  def remove_size(inventory, item_name, size) do
    Enum.map(inventory, fn item ->
      if is_map(item) and Map.get(item, :name) == item_name do

        tallas =
          case Map.get(item, :quantity_by_size) do
            mapa when is_map(mapa) -> mapa
            _ -> %{}
          end

        nuevas_tallas =
          Map.delete(tallas, size)

        Map.put(item, :quantity_by_size, nuevas_tallas)

      else
        item
      end
    end)
  end

  def sort_by_price(nil), do: []

  def sort_by_price(inventory) do
    Enum.sort_by(inventory, fn item ->
      if is_map(item) do
        Map.get(item, :price)
      else
        nil
      end
    end)
  end

  def with_missing_price(nil), do: []

  def with_missing_price(inventory) do
    Enum.filter(inventory, fn item ->
      is_map(item) and is_nil(Map.get(item, :price))
    end)
  end

  def increase_quantity(nil, _n), do: nil
  def increase_quantity(item, nil), do: item

  def increase_quantity(item, n) do
    tallas =
      case Map.get(item, :quantity_by_size) do
        mapa when is_map(mapa) -> mapa
        _ -> %{}
      end

    nuevas_tallas =
      Enum.map(tallas, fn {size, quantity} ->
        {size, quantity + n}
      end)
      |> Map.new()

    Map.put(item, :quantity_by_size, nuevas_tallas)
  end

  def total_quantity(nil), do: 0

  def total_quantity(item) do
    tallas =
      case Map.get(item, :quantity_by_size) do
        mapa when is_map(mapa) -> mapa
        _ -> %{}
      end

    tallas
    |> Map.values()
    |> Enum.sum()
  end
end

defmodule SentinelCpWeb.ServicesLive.New do
  use SentinelCpWeb, :live_view

  alias SentinelCp.{Audit, Orgs, Projects, Services}

  @impl true
  def mount(%{"project_slug" => slug} = params, _session, socket) do
    org = resolve_org(params)

    case Projects.get_project_by_slug(slug) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/orgs")}

      project ->
        {:ok,
         assign(socket,
           page_title: "New Service — #{project.name}",
           org: org,
           project: project,
           route_type: "upstream",
           show_retry: false,
           show_cache: false,
           show_rate_limit: false,
           show_health_check: false
         )}
    end
  end

  @impl true
  def handle_event("switch_route_type", %{"type" => type}, socket) do
    {:noreply, assign(socket, route_type: type)}
  end

  @impl true
  def handle_event("toggle_section", %{"section" => section}, socket) do
    key = String.to_existing_atom("show_#{section}")
    {:noreply, assign(socket, [{key, !socket.assigns[key]}])}
  end

  @impl true
  def handle_event("create_service", params, socket) do
    project = socket.assigns.project

    attrs = %{
      project_id: project.id,
      name: params["name"],
      description: params["description"],
      route_path: params["route_path"],
      timeout_seconds: parse_int(params["timeout_seconds"])
    }

    attrs =
      case socket.assigns.route_type do
        "upstream" ->
          Map.put(attrs, :upstream_url, params["upstream_url"])

        "static" ->
          attrs
          |> Map.put(:respond_status, parse_int(params["respond_status"]))
          |> Map.put(:respond_body, params["respond_body"])
      end

    attrs = maybe_put_map(attrs, :retry, params, "retry")
    attrs = maybe_put_map(attrs, :cache, params, "cache")
    attrs = maybe_put_map(attrs, :rate_limit, params, "rate_limit")
    attrs = maybe_put_map(attrs, :health_check, params, "health_check")

    case Services.create_service(attrs) do
      {:ok, service} ->
        Audit.log_user_action(socket.assigns.current_user, "create", "service", service.id,
          project_id: project.id
        )

        show_path = service_show_path(socket.assigns.org, project, service)

        {:noreply,
         socket
         |> put_flash(:info, "Service created.")
         |> push_navigate(to: show_path)}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
          |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)

        {:noreply, put_flash(socket, :error, "Failed: #{errors}")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4 max-w-2xl">
      <h1 class="text-xl font-bold">Create Service</h1>

      <.k8s_section>
        <form phx-submit="create_service" class="space-y-6">
          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Name</span></label>
            <input
              type="text"
              name="name"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. API Backend"
            />
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Description</span></label>
            <textarea
              name="description"
              rows="2"
              class="textarea textarea-bordered textarea-sm w-full"
              placeholder="Optional description"
            ></textarea>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Route Path</span></label>
            <input
              type="text"
              name="route_path"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. /api/v1/*"
            />
            <label class="label">
              <span class="label-text-alt text-base-content/50">Must start with /</span>
            </label>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Route Type</span></label>
            <div class="flex gap-2">
              <button
                type="button"
                phx-click="switch_route_type"
                phx-value-type="upstream"
                class={["btn btn-sm", (@route_type == "upstream" && "btn-primary") || "btn-ghost"]}
              >
                Upstream Proxy
              </button>
              <button
                type="button"
                phx-click="switch_route_type"
                phx-value-type="static"
                class={["btn btn-sm", (@route_type == "static" && "btn-primary") || "btn-ghost"]}
              >
                Static Response
              </button>
            </div>
          </div>

          <div :if={@route_type == "upstream"} class="form-control">
            <label class="label"><span class="label-text font-medium">Upstream URL</span></label>
            <input
              type="text"
              name="upstream_url"
              required
              class="input input-bordered input-sm w-full"
              placeholder="e.g. http://api-backend:8080"
            />
          </div>

          <div :if={@route_type == "static"} class="space-y-3">
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Response Status</span></label>
              <input
                type="number"
                name="respond_status"
                required
                class="input input-bordered input-sm w-32"
                placeholder="200"
                min="100"
                max="599"
              />
            </div>
            <div class="form-control">
              <label class="label"><span class="label-text font-medium">Response Body</span></label>
              <textarea
                name="respond_body"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full font-mono"
                placeholder="OK"
              ></textarea>
            </div>
          </div>

          <div class="form-control">
            <label class="label"><span class="label-text font-medium">Timeout (seconds)</span></label>
            <input
              type="number"
              name="timeout_seconds"
              class="input input-bordered input-sm w-32"
              placeholder="30"
              min="1"
            />
          </div>

          <%!-- Advanced Sections --%>
          <div class="divider text-xs text-base-content/50">Advanced Settings</div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="retry"
              class="btn btn-ghost btn-xs"
            >
              {if @show_retry, do: "▼", else: "▶"} Retry Policy
            </button>
            <div :if={@show_retry} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Attempts</span></label>
                <input
                  type="number"
                  name="retry[attempts]"
                  class="input input-bordered input-xs w-24"
                  placeholder="3"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Backoff</span></label>
                <input
                  type="text"
                  name="retry[backoff]"
                  class="input input-bordered input-xs w-40"
                  placeholder="exponential"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="cache"
              class="btn btn-ghost btn-xs"
            >
              {if @show_cache, do: "▼", else: "▶"} Cache
            </button>
            <div :if={@show_cache} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">TTL (seconds)</span></label>
                <input
                  type="number"
                  name="cache[ttl]"
                  class="input input-bordered input-xs w-24"
                  placeholder="3600"
                  min="0"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Vary</span></label>
                <input
                  type="text"
                  name="cache[vary]"
                  class="input input-bordered input-xs w-48"
                  placeholder="Accept-Encoding"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="rate_limit"
              class="btn btn-ghost btn-xs"
            >
              {if @show_rate_limit, do: "▼", else: "▶"} Rate Limit
            </button>
            <div :if={@show_rate_limit} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Requests</span></label>
                <input
                  type="number"
                  name="rate_limit[requests]"
                  class="input input-bordered input-xs w-24"
                  placeholder="100"
                  min="1"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Window</span></label>
                <input
                  type="text"
                  name="rate_limit[window]"
                  class="input input-bordered input-xs w-24"
                  placeholder="60s"
                />
              </div>
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">By</span></label>
                <input
                  type="text"
                  name="rate_limit[by]"
                  class="input input-bordered input-xs w-32"
                  placeholder="client_ip"
                />
              </div>
            </div>
          </div>

          <div>
            <button
              type="button"
              phx-click="toggle_section"
              phx-value-section="health_check"
              class="btn btn-ghost btn-xs"
            >
              {if @show_health_check, do: "▼", else: "▶"} Health Check
            </button>
            <div :if={@show_health_check} class="ml-4 mt-2 space-y-2">
              <div class="form-control">
                <label class="label"><span class="label-text text-xs">Path</span></label>
                <input
                  type="text"
                  name="health_check[path]"
                  class="input input-bordered input-xs w-48"
                  placeholder="/health"
                />
              </div>
              <div class="form-control">
                <label class="label">
                  <span class="label-text text-xs">Interval (seconds)</span>
                </label>
                <input
                  type="number"
                  name="health_check[interval]"
                  class="input input-bordered input-xs w-24"
                  placeholder="10"
                  min="1"
                />
              </div>
            </div>
          </div>

          <div class="flex gap-2 pt-4">
            <button type="submit" class="btn btn-primary btn-sm">Create Service</button>
            <.link navigate={project_services_path(@org, @project)} class="btn btn-ghost btn-sm">
              Cancel
            </.link>
          </div>
        </form>
      </.k8s_section>
    </div>
    """
  end

  defp resolve_org(%{"org_slug" => slug}), do: Orgs.get_org_by_slug(slug)
  defp resolve_org(_), do: nil

  defp project_services_path(%{slug: org_slug}, project),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services"

  defp project_services_path(nil, project),
    do: ~p"/projects/#{project.slug}/services"

  defp service_show_path(%{slug: org_slug}, project, service),
    do: ~p"/orgs/#{org_slug}/projects/#{project.slug}/services/#{service.id}"

  defp service_show_path(nil, project, service),
    do: ~p"/projects/#{project.slug}/services/#{service.id}"

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(n) when is_integer(n), do: n

  defp maybe_put_map(attrs, key, params, param_key) do
    case params[param_key] do
      nil ->
        attrs

      %{} = map ->
        cleaned = map |> Enum.reject(fn {_, v} -> v == "" || is_nil(v) end) |> Map.new()

        if cleaned == %{} do
          attrs
        else
          # Convert numeric string values to integers where possible
          cleaned =
            Map.new(cleaned, fn {k, v} ->
              case Integer.parse(v) do
                {n, ""} -> {k, n}
                _ -> {k, v}
              end
            end)

          Map.put(attrs, key, cleaned)
        end

      _ ->
        attrs
    end
  end
end

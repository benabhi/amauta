defmodule AmautaWeb.Components.DirectUpload do
  @moduledoc """
  Subida directa al almacenamiento (RF-ARC-001): el archivo va del
  navegador a S3 con URLs prefirmadas, sin pasar por la aplicación. Se
  elige, se arrastra o se pega (con el foco en la zona), muestra el
  progreso, sube por partes los archivos grandes reintentando cada parte y,
  si se corta, al volver a elegir el mismo archivo sigue desde donde quedó.

  Cuando el archivo queda verificado (`Amauta.Files.complete_upload/2`),
  avisa a la vista que lo contiene:

      <.live_component
        module={AmautaWeb.Components.DirectUpload}
        id="avatar-upload"
        current_scope={@current_scope}
        purpose="avatar"
        accept="image/png,image/jpeg,image/gif,image/webp"
        label={gettext("Profile photo")}
      />

      def handle_info({AmautaWeb.Components.DirectUpload, "avatar-upload", {:uploaded, file}}, socket)

  Con `variant="button"` es un botón compacto («Adjuntar archivo») que
  también acepta arrastrar y pegar, para los formularios.
  """
  use AmautaWeb, :live_component

  alias Amauta.Actions
  alias Amauta.Files.Actions.{CompleteUpload, StartUpload}
  alias Amauta.Files.Purpose

  @impl true
  def mount(socket), do: {:ok, assign(socket, status: :idle, error: nil, filename: nil)}

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:owner_id, fn -> nil end)
     |> assign_new(:accept, fn -> nil end)
     |> assign_new(:hint, fn -> nil end)
     |> assign_new(:variant, fn -> "zone" end)
     |> assign(:max_size, Purpose.limits(assigns.purpose).max_size)}
  end

  @impl true
  def handle_event("start", params, socket) do
    input = %{
      "purpose" => socket.assigns.purpose,
      "owner_id" => socket.assigns.owner_id,
      "filename" => params["filename"],
      "size" => params["size"],
      "declared_type" => params["declared_type"]
    }

    case Actions.run(StartUpload, socket.assigns.current_scope, input) do
      {:ok, %{file: file, plan: plan}} ->
        {:reply, Map.put(plan, :file_id, file.id),
         assign(socket, status: :uploading, error: nil, filename: file.filename)}

      {:error, reason} ->
        {:reply, %{error: true}, assign(socket, status: :error, error: message(reason, socket))}
    end
  end

  def handle_event("complete", %{"file_id" => id}, socket) do
    case Actions.run(CompleteUpload, socket.assigns.current_scope, %{"file_id" => id}) do
      {:ok, %{status: "ready"} = file} ->
        send(self(), {__MODULE__, socket.assigns.id, {:uploaded, file}})
        {:noreply, assign(socket, status: :done, error: nil)}

      {:ok, %{rejection_reason: reason}} ->
        {:noreply,
         assign(socket, status: :error, error: message(String.to_existing_atom(reason), socket))}

      {:error, reason} ->
        {:noreply, assign(socket, status: :error, error: message(reason, socket))}
    end
  end

  def handle_event("failed", _params, socket),
    do: {:noreply, assign(socket, status: :error, error: message(:network, socket))}

  defp message(:too_large, socket) do
    mb = Float.round(socket.assigns.max_size / (1024 * 1024), 1)
    gettext("The file is too big (maximum %{size} MB).", size: AmautaWeb.Format.number(mb))
  end

  defp message(:type_not_allowed, _socket), do: gettext("That type of file is not allowed here.")

  defp message(:mismatch, _socket),
    do: gettext("The content of the file doesn't match its extension.")

  defp message(:unknown, _socket), do: gettext("We couldn't recognize the type of file.")
  defp message(:empty, _socket), do: gettext("The file is empty.")

  defp message(:network, _socket),
    do: gettext("The upload was interrupted. Choose the file again to continue where it stopped.")

  defp message(_reason, _socket), do: gettext("The file could not be uploaded. Try again.")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} phx-hook=".DirectUpload" phx-target={@myself} class="grid gap-2">
      <label
        :if={@variant == "zone"}
        data-drop
        tabindex="0"
        for={"#{@id}-input"}
        class={[
          "flex min-h-28 cursor-pointer flex-col items-center justify-center gap-2 rounded-card",
          "border-2 border-dashed border-line bg-surface px-4 py-6 text-center",
          "hover:border-primary focus-visible:border-primary data-[dragging]:border-primary",
          "data-[dragging]:bg-anil-soft"
        ]}
      >
        <.icon name="upload-simple" class="size-6 text-ink-muted" />
        <span class="font-semibold">{@label}</span>
        <span class="text-sm text-ink-muted">
          {gettext("Choose a file, drag it here or paste it.")}
        </span>
        <span :if={@hint} class="text-xs text-ink-muted">{@hint}</span>
      </label>
      <label
        :if={@variant == "button"}
        data-drop
        tabindex="0"
        for={"#{@id}-input"}
        title={@hint}
        class={[
          "inline-flex min-h-11 cursor-pointer items-center gap-2 justify-self-start rounded-control px-3",
          "text-sm font-semibold text-ink-muted hover:bg-surface-sunken hover:text-ink",
          "focus-visible:outline-2 focus-visible:outline-primary data-[dragging]:bg-anil-soft"
        ]}
      >
        <.icon name="paperclip" class="size-5" /> {@label}
      </label>
      <input id={"#{@id}-input"} type="file" accept={@accept} class="sr-only" />

      <div :if={@status == :uploading} class="grid gap-1" aria-live="polite">
        <span class="truncate text-sm">{gettext("Uploading %{name}…", name: @filename)}</span>
        <div
          id={"#{@id}-progress"}
          phx-update="ignore"
          role="progressbar"
          aria-valuemin="0"
          aria-valuemax="100"
          aria-label={gettext("Upload progress")}
          class="h-2 overflow-hidden rounded-full bg-surface-sunken"
        >
          <div
            data-progress
            class="h-full origin-left scale-x-0 bg-primary motion-safe:transition-transform motion-safe:duration-fast"
          />
        </div>
      </div>

      <p
        :if={@status == :done and @variant == "zone"}
        class="flex items-center gap-2 text-sm text-chilca-deep"
        aria-live="polite"
      >
        <.icon name="check-circle" class="size-4" /> {gettext("Uploaded.")}
      </p>

      <p :if={@error} role="alert" class="flex items-center gap-2 text-sm text-cochinilla-deep">
        <.icon name="warning-circle" class="size-4" /> {@error}
      </p>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".DirectUpload">
        // Subida directa a S3 con URLs prefirmadas (RF-ARC-001).
        const ATTEMPTS = 3

        export default {
          mounted() {
            this.input = this.el.querySelector("input[type=file]")
            this.drop = this.el.querySelector("[data-drop]")

            this.input.addEventListener("change", () => {
              const file = this.input.files[0]
              if (file) this.upload(file)
              this.input.value = ""
            })

            for (const name of ["dragenter", "dragover"]) {
              this.drop.addEventListener(name, (e) => {
                e.preventDefault()
                this.drop.dataset.dragging = ""
              })
            }

            for (const name of ["dragleave", "drop"]) {
              this.drop.addEventListener(name, (e) => {
                e.preventDefault()
                delete this.drop.dataset.dragging
              })
            }

            this.drop.addEventListener("drop", (e) => {
              const file = e.dataTransfer?.files?.[0]
              if (file) this.upload(file)
            })

            // Pegar desde el portapapeles con el foco en la zona.
            this.drop.addEventListener("paste", (e) => {
              const file = e.clipboardData?.files?.[0]
              if (file) {
                e.preventDefault()
                this.upload(file)
              }
            })

            this.drop.addEventListener("keydown", (e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault()
                this.input.click()
              }
            })
          },

          upload(file) {
            const params = {filename: file.name, size: file.size, declared_type: file.type}

            this.pushEventTo(this.el, "start", params, async (plan) => {
              if (plan.error) return

              try {
                if (plan.mode === "single") {
                  await this.retry(() => this.put(plan.url, file, plan.headers, 0, file.size))
                } else {
                  await this.multipart(plan, file)
                }
                this.pushEventTo(this.el, "complete", {file_id: plan.file_id})
              } catch (_error) {
                this.pushEventTo(this.el, "failed", {})
              }
            })
          },

          async multipart(plan, file) {
            let sent = plan.done.reduce((sum, n) => sum + this.partLength(file.size, plan.part_size, n), 0)

            for (const part of plan.parts) {
              const start = (part.number - 1) * plan.part_size
              const blob = file.slice(start, start + plan.part_size)
              await this.retry(() => this.put(part.url, blob, {}, sent, file.size))
              sent += blob.size
            }
          },

          partLength(size, partSize, number) {
            return Math.min(partSize, size - (number - 1) * partSize)
          },

          async retry(fun) {
            for (let attempt = 1; ; attempt++) {
              try {
                return await fun()
              } catch (error) {
                if (attempt >= ATTEMPTS) throw error
                await new Promise((resolve) => setTimeout(resolve, 1000 * attempt))
              }
            }
          },

          put(url, body, headers, base, total) {
            return new Promise((resolve, reject) => {
              const xhr = new XMLHttpRequest()
              xhr.open("PUT", url)
              for (const [name, value] of Object.entries(headers || {})) xhr.setRequestHeader(name, value)
              xhr.upload.onprogress = (e) => this.progress((base + e.loaded) / total)
              xhr.onload = () => (xhr.status < 300 ? resolve() : reject(new Error(String(xhr.status))))
              xhr.onerror = () => reject(new Error("network"))
              xhr.send(body)
            })
          },

          progress(ratio) {
            const value = Math.min(1, Math.max(0, ratio))
            const bar = this.el.querySelector("[data-progress]")
            if (!bar) return
            bar.style.transform = `scaleX(${value})`
            bar.parentElement.setAttribute("aria-valuenow", Math.round(value * 100))
          }
        }
      </script>
    </div>
    """
  end
end

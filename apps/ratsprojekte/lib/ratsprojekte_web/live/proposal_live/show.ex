defmodule RatsprojekteWeb.ProposalLive.Show do
  use RatsprojekteWeb, :live_view

  alias Ratsprojekte.Repo
  alias Ratsprojekte.Schemas.{PendingProposal, Projekt, Realisierungsstrang}
  alias RatsprojekteWeb.NavAssigns
  import Ecto.Query

  @impl true
  def mount(params, _session, socket) do
    projekt_slug = params["projekt_slug"]

    # Bei geschachtelter URL (/projekte/:projekt_slug/...) zuerst das Projekt prüfen —
    # existiert es nicht, hat auch die Proposal-Suche in diesem Scope keinen Sinn.
    projekt =
      if projekt_slug,
        do: Repo.one(from(p in Projekt, where: p.slug == ^projekt_slug)),
        else: nil

    if projekt_slug != nil and projekt == nil do
      {:ok, socket |> put_flash(:error, "Projekt nicht gefunden") |> redirect(to: ~p"/")}
    else
      projekt_id = if projekt, do: projekt.id, else: nil
      proposal = fetch_proposal(params["id"], projekt_id)
      mount_proposal(socket, proposal, projekt, projekt_slug)
    end
  end

  defp fetch_proposal(id, projekt_id) do
    base =
      from(pp in PendingProposal,
        where: pp.id == ^id,
        preload: [:projekt]
      )

    if projekt_id do
      Repo.one(from(pp in base, where: pp.projekt_id == ^projekt_id))
    else
      Repo.one(base)
    end
  end

  defp mount_proposal(socket, nil, _projekt, projekt_slug) do
    {:ok,
     socket
     |> put_flash(:error, "Vorschlag nicht gefunden")
     |> redirect(to: back_path(projekt_slug))}
  end

  defp mount_proposal(socket, proposal, nil, nil) do
    # Top-level add_projekt-Vorschlag ohne Eltern-Projekt.
    existing_labels = MapSet.new()

    {:ok,
     socket
     |> NavAssigns.attach(:vorschlaege)
     |> assign(projekt: proposal.projekt, proposal: proposal, existing_labels: existing_labels)
     |> assign_form()}
  end

  defp mount_proposal(socket, proposal, projekt, _projekt_id) do
    existing_labels = existing_labels(projekt.id)

    {:ok,
     socket
     |> NavAssigns.attach(:projekte)
     |> assign(projekt: projekt, proposal: proposal, existing_labels: existing_labels)
     |> assign_form()}
  end

  # Decide: Accept legt atomar den Realisierungsstrang bzw. das Projekt an (GO-Prinzip).
  # Reject: nur Status-Update mit Kommentar (empfohlen).
  @impl true
  def handle_event("decide", %{"aktion" => aktion, "kommentar" => kommentar}, socket) do
    case aktion do
      "accept" -> accept(socket, kommentar)
      "reject" -> reject(socket, kommentar)
      _ -> {:noreply, put_flash(socket, :error, "Unbekannte Aktion: #{aktion}")}
    end
  end

  defp accept(socket, kommentar) do
    %{proposal: proposal, projekt: projekt} = socket.assigns

    case proposal.typ do
      :add_realisierungsstrang ->
        strang_attrs = Map.put(proposal.payload, "projekt_id", projekt.id)
        apply_proposal(proposal, Realisierungsstrang, strang_attrs, kommentar, socket)

      :add_projekt ->
        apply_proposal(proposal, Projekt, proposal.payload, kommentar, socket)

      :change_status ->
        apply_status_change(proposal, projekt, kommentar, socket)
    end
  end

  # Atomar: Record anlegen + Proposal auf approved setzen. Schlägt das
  # Anlegen fehl, bleibt das Proposal `pending` (Idempotenz).
  defp apply_proposal(proposal, schema_mod, attrs, kommentar, socket) do
    decision_attrs = %{
      status: :approved,
      entschieden_am: DateTime.utc_now(),
      entschieden_von: "stadtrat",
      entscheidungskommentar: blank_to_nil(kommentar)
    }

    result =
      Repo.transaction(fn ->
        record = Repo.insert!(schema_mod.changeset(struct(schema_mod), attrs))
        _ = record

        Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
      end)

    handle_apply_result(result, proposal.typ, socket)
  end

  # :change_status — statt neuem Record wird das bestehende Projekt
  # aktualisiert (Status + ggf. abgeschlossen_am / verworfen_am / verworfen_grund).
  defp apply_status_change(proposal, projekt, kommentar, socket) do
    status = String.to_existing_atom(proposal.payload["status"])
    datum = parse_date(proposal.payload["datum"])
    verworfen_grund = proposal.payload["verworfen_grund"]

    update_attrs = %{status: status}

    update_attrs =
      if datum, do: put_date_field(update_attrs, status, datum), else: update_attrs

    update_attrs =
      if verworfen_grund,
        do: Map.put(update_attrs, :verworfen_grund, verworfen_grund),
        else: update_attrs

    decision_attrs = %{
      status: :approved,
      entschieden_am: DateTime.utc_now(),
      entschieden_von: "stadtrat",
      entscheidungskommentar: blank_to_nil(kommentar)
    }

    result =
      Repo.transaction(fn ->
        Repo.update!(Projekt.changeset(projekt, update_attrs))
        Repo.update!(PendingProposal.decision_changeset(proposal, decision_attrs))
      end)

    handle_apply_result(result, proposal.typ, socket)
  end

  defp put_date_field(attrs, :abgeschlossen, datum),
    do: Map.put(attrs, :abgeschlossen_am, datum)

  defp put_date_field(attrs, :verworfen, datum), do: Map.put(attrs, :verworfen_am, datum)
  defp put_date_field(attrs, _, _), do: attrs

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end

  defp handle_apply_result({:ok, _}, typ, socket) do
    %{proposal: proposal} = socket.assigns

    updated = Repo.preload(Repo.get!(PendingProposal, proposal.id), [:projekt])

    {:noreply, socket |> put_flash(:info, accept_flash(typ)) |> assign(proposal: updated)}
  end

  defp handle_apply_result({:error, changeset}, _typ, socket) do
    {:noreply, put_flash(socket, :error, "Fehler beim Accept: #{format_errors(changeset)}")}
  end

  defp accept_flash(:add_projekt), do: "Vorschlag angenommen — Projekt angelegt."

  defp accept_flash(:add_realisierungsstrang),
    do: "Vorschlag angenommen — Realisierungsstrang angelegt."

  defp accept_flash(:change_status), do: "Vorschlag angenommen — Projektstatus geändert."

  defp reject(socket, kommentar) do
    %{proposal: proposal} = socket.assigns

    decision_attrs = %{
      status: :rejected,
      entschieden_am: DateTime.utc_now(),
      entschieden_von: "stadtrat",
      entscheidungskommentar: blank_to_nil(kommentar)
    }

    proposal
    |> PendingProposal.decision_changeset(decision_attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, "Vorschlag abgelehnt.")
         |> assign(proposal: updated)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, "Fehler beim Reject: #{format_errors(changeset)}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="page">
      <h1 class="page-title">
        Vorschlag: {payload_field(@proposal.payload, "titel")}
      </h1>
      <p style="font-size: var(--text-sm); color: var(--color-text-muted); margin-bottom: var(--space-3);">
        {@proposal.typ} · vorgeschlagen von {@proposal.vorgeschlagen_von} am {format_dt(
          @proposal.vorgeschlagen_am
        )}
      </p>
      <div class="badges" style="margin-bottom: var(--space-6);">
        <.badge kind={:proposal} value={@proposal.status} />
      </div>

      <div class="section-label flush">
        {payload_heading(@proposal.typ)}
      </div>
      <div class="payload-box">
        <%= case @proposal.typ do %>
          <% :add_realisierungsstrang -> %>
            <.payload_row label="Label" value={payload_field(@proposal.payload, "label")} />
            <.payload_row label="Titel" value={payload_field(@proposal.payload, "titel")} />
            <.payload_row
              label="Beschreibung"
              value={payload_field(@proposal.payload, "beschreibung")}
            />
            <.payload_row
              label="Rechtliche Grundlage"
              value={payload_field(@proposal.payload, "rechtliche_grundlage")}
            />
            <.payload_row label="Bedingung" value={payload_field(@proposal.payload, "bedingung")} />
          <% :add_projekt -> %>
            <.payload_row label="Titel" value={payload_field(@proposal.payload, "titel")} />
            <.payload_row
              label="Beschreibung"
              value={payload_field(@proposal.payload, "beschreibung")}
            />
            <.payload_row label="Priorität" value={payload_field(@proposal.payload, "prioritaet")} />
          <% :change_status -> %>
            <.payload_row label="Neuer Status" value={payload_field(@proposal.payload, "status")} />
            <.payload_row label="Datum" value={payload_field(@proposal.payload, "datum")} />
            <.payload_row
              label="Verworfungsgrund"
              value={payload_field(@proposal.payload, "verworfen_grund")}
            />
        <% end %>
      </div>

      <%= if @proposal.typ == :add_realisierungsstrang and
              label_conflict?(@proposal.payload, @existing_labels) do %>
        <div class="warning-hint">
          ⚠ Hinweis: Es existiert bereits ein Realisierungsstrang mit Label „#{payload_field(
            @proposal.payload,
            "label"
          )}".
          Doppelter Strang möglich — bewusst kein Unique-Index (Idempotenz, die AI darf es mit besseren Argumenten nochmal versuchen).
        </div>
      <% end %>

      <div class="section-label flush spaced">
        Begründung (Quellenpflicht)
      </div>
      <div class="callout">
        {@proposal.begruendung}
      </div>

      <%= if @proposal.quellen do %>
        <div class="section-label flush spaced">Quellen</div>
        <div class="quellen-text">{@proposal.quellen}</div>
      <% end %>

      <%= if @proposal.status == :pending do %>
        <div class="section-label flush spaced">
          Entscheidung (GO-Prinzip)
        </div>
        <.form for={@form} phx-submit="decide" id="decision-form" class="decision-form">
          <textarea
            name="kommentar"
            placeholder="Kommentar (optional bei Accept, empfohlen bei Reject — Lern-Effekt für die AI)"
            class="decision-textarea"
          ></textarea>
          <div class="decision-actions">
            <button type="submit" name="aktion" value="accept" class="btn btn-primary">
              ✓ Accept ({accept_button_label(@proposal.typ)})
            </button>
            <button type="submit" name="aktion" value="reject" class="btn btn-danger">
              ✗ Reject
            </button>
          </div>
        </.form>
      <% else %>
        <div class="section-label flush spaced">Entscheidung</div>
        <div class="info-box">
          <strong>Status:</strong> {@proposal.status}<br />
          <strong>Entschieden am:</strong> {format_dt(@proposal.entschieden_am)}<br />
          <strong>Entschieden von:</strong> {@proposal.entschieden_von}
          <%= if @proposal.entscheidungskommentar do %>
            <br /><strong>Kommentar:</strong> {@proposal.entscheidungskommentar}
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  # --- Helpers ---

  defp back_path(nil), do: ~p"/proposals"
  defp back_path(projekt_slug), do: ~p"/projekte/#{projekt_slug}/proposals"

  defp payload_heading(:add_projekt), do: "Vorgeschlagenes Projekt"
  defp payload_heading(:add_realisierungsstrang), do: "Vorgeschlagener Realisierungsstrang"
  defp payload_heading(:change_status), do: "Vorgeschlagene Statusänderung"

  defp accept_button_label(:add_projekt), do: "Projekt anlegen"
  defp accept_button_label(:add_realisierungsstrang), do: "Strang anlegen"
  defp accept_button_label(:change_status), do: "Status ändern"

  defp existing_labels(projekt_id) do
    query =
      from(rs in Realisierungsstrang,
        where: rs.projekt_id == ^projekt_id,
        select: rs.label
      )

    labels = Repo.all(query)

    labels
    |> Enum.reject(&is_nil/1)
    |> MapSet.new()
  end

  defp label_conflict?(payload, existing_labels) do
    label = payload_field(payload, "label")
    label != "" and MapSet.member?(existing_labels, label)
  end

  defp payload_field(payload, key) do
    case payload[key] do
      value when is_binary(value) -> value
      _ -> ""
    end
  end

  defp format_dt(nil), do: "—"
  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%d.%m.%Y %H:%M")

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp assign_form(socket) do
    form = Phoenix.Component.to_form(%{}, as: :decision)
    assign(socket, form: form)
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  attr(:label, :string, required: true)
  attr(:value, :any, required: true)

  defp payload_row(assigns) do
    value = assigns.value
    assigns = assign(assigns, :value, value)

    ~H"""
    <div class="payload-row">
      <span class="payload-row-label">
        {@label}:
      </span>
      <span class="payload-row-value">{present_or_dash(@value)}</span>
    </div>
    """
  end

  defp present_or_dash(nil), do: "—"
  defp present_or_dash(""), do: "—"
  defp present_or_dash(value), do: value
end

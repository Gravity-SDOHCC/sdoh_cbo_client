// app/javascript/controllers/task_action_controller.js
//
// Drives the "Accept / Update Task" modal on the CBO dashboard: it reveals the
// fields that only apply to the status being set.
//
// Replaces the inline <script> that used to live in
// _request_action_modal.html.erb. That script looked its container up with
// document.querySelector(".status-reason-container"), and the dashboard renders
// one modal per task, so it always toggled the FIRST container on the page
// rather than the one in the open modal. Everything here is scoped to
// this.element, which is the modal itself.
//
// The enrollment and findings containers are only rendered in the modal that
// offers "completed", so every reference to them is guarded.
import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["statusSelect", "statusReasonContainer", "enrollmentContainer", "findingsContainer"];

  connect() {
    this.statusChanged();
  }

  statusChanged() {
    const status = this.hasStatusSelectTarget ? this.statusSelectTarget.value : "";

    if (this.hasStatusReasonContainerTarget) {
      this.toggle(this.statusReasonContainerTarget, status === "rejected" || status === "cancelled");
    }

    // Program enrollment status is an outcome of the referral, so it is asked
    // for only on the way to completed.
    if (this.hasEnrollmentContainerTarget) {
      this.toggle(this.enrollmentContainerTarget, status === "completed");
    }

    // So are the assessment findings the referral is closed with.
    if (this.hasFindingsContainerTarget) {
      this.toggle(this.findingsContainerTarget, status === "completed");
    }
  }

  toggle(element, visible) {
    element.style.display = visible ? "block" : "none";
  }
}

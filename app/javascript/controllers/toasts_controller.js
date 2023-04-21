import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="toasts"
export default class extends Controller {
  connect() {
    this.show();
  }

  show() {
    this.element.classList.add("show");

    setTimeout(() => {
      this.hide();
    }, 5000);
  }

  hide() {
    this.element.classList.remove("show");
    setTimeout(() => {
      this.element.remove();
    }, 500);
  }
}

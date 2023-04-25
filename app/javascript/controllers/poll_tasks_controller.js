import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="poll-tasks"
export default class extends Controller {
  initialize() {
    const pollUrl = this.element.dataset.pollUrl;
    if (pollUrl) {
      this.pollTasks(pollUrl);
    }
  }

  pollTasks(pollUrl) {
    fetch(pollUrl)
      .then((response) => {
        if (response.ok) {
          return response.json();
        } else {
          throw new Error("Failed to poll tasks");
        }
      })
      .then((response) => {
        if (reponse.error){
          console.log(response.error);
        } else {
          const tables = [
            { id: "active-tasks-table", data: response.active_tasks },
            { id: "completed-tasks-table", data: response.completed_tasks },
            { id: "cancelled-tasks-table", data: response.cancelled_tasks },
          ];

          tables.forEach((table) => {
            const tableElement = document.getElementById(table.id);
            if (tableElement && table.data) {
              tableElement.innerHTML = table.data;
            }
          });

        };

        setTimeout(() => this.pollTasks(pollUrl), 10000);
      })
      .catch((error) => {
        console.error(error);
        setTimeout(() => this.pollTasks(pollUrl), 10000);
      });
  }
}

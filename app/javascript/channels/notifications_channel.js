import consumer from "./consumer"

consumer.subscriptions.create("NotificationsChannel", {
  received(data) {
    const menuItems = [
      { id: "service-requests", notificationId: "ehr_task_notifications", menuLabel: "Service Requests" },
      { id: "our-tasks", notificationId: "cp_task_notifications", menuLabel: "Our Tasks" },
    ];

    menuItems.forEach((menuItem) => {
      const notificationCount = document.getElementById(`${menuItem.id}-notification-count`);
      const notifications = JSON.parse(data[menuItem.notificationId] || "[]");
      if (notifications.length > 0) {
        let count = parseInt(notificationCount.innerText, 10) || 0;
        count += notifications.length;

        notificationCount.innerText = count;
        notificationCount.style.display = "inline-block";

        const dropdown = document.getElementById(`${menuItem.id}-notification-dropdown`);
        notifications.forEach((notification) => {
          const message = notification[0];
          const id = notification[1];
          const row = document.getElementById(`task-row-${id}`);
          const list = document.createElement("li")
          const item = document.createElement("a");
          item.classList.add("dropdown-item");
          item.href = "#";
          item.innerText = message;
          list.appendChild(item);
          dropdown.appendChild(list);
          item.addEventListener("click", (event) => {
            if (row) {
              row.classList.add("bg-info");
              setTimeout(() => row.classList.remove("bg-info"), 10000);
            }
            dropdown.removeChild(event.target.parentElement);
            dropdown.toggleAttribute("display", "none");

            count--;
            if (count === 0) {
              notificationCount.style.display = "none";
            }
            notificationCount.innerText = count;
          });

        });
      }
    });
  }
});

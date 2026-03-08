async function loadUsers() {
  try {
    const response = await fetch(window.USERS_API);
    if (!response.ok) throw new Error('Network response was not ok');
    const { users } = await response.json();
    const tbody = document.querySelector('#usersTable tbody');
    tbody.innerHTML = '';
    users.forEach(u => {
      const row = document.createElement('tr');
      row.innerHTML = `
        <td>${u.name}</td>
        <td>${u.email}</td>
        <td>${u.status}</td>
        <td>
          <div class="table-actions">
            <a class="btn btn-outline btn-sm" href="/administration/users/${u.id}/view/"><i class="fa-regular fa-eye"></i> View</a>
            <a class="btn btn-outline btn-sm" href="/administration/users/${u.id}/edit/"><i class="fa-regular fa-pen-to-square"></i> Edit</a>
            <a class="btn btn-outline btn-sm" href="/administration/users/${u.id}/support-chat/"><i class="fa-regular fa-comments"></i> Support</a>
            <a class="btn btn-outline btn-sm" href="/administration/users/${u.id}/vehicles/"><i class="fa-solid fa-car"></i> Vehicles</a>
          </div>
        </td>`;
      tbody.appendChild(row);
    });
  } catch (error) {
    console.error('Error loading users:', error);
  }
}

document.addEventListener('DOMContentLoaded', loadUsers);
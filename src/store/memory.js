class MemoryStore {
  constructor() {
    this.kind = 'memory';
    this.todos = new Map();
    this.nextId = 1;
  }

  async ping() {}

  async list() {
    return [...this.todos.values()];
  }

  async create(title) {
    const todo = { id: this.nextId++, title, done: false };
    this.todos.set(todo.id, todo);
    return todo;
  }

  async update(id, { done }) {
    const todo = this.todos.get(id);
    if (!todo) return null;
    todo.done = done;
    return todo;
  }

  async remove(id) {
    return this.todos.delete(id);
  }

  async close() {}
}

module.exports = { MemoryStore };

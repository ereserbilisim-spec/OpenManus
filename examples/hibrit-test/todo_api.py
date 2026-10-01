from flask import Flask, request, jsonify

app = Flask(__name__)

# In-memory todo listesi
todos = []
todo_id_counter = 1

@app.route('/todos', methods=['GET'])
def get_todos():
    return jsonify(todos)

@app.route('/todos', methods=['POST'])
def create_todo():
    global todo_id_counter
    data = request.get_json()
    if not data or 'title' not in data:
        return jsonify({'error': 'title required'}), 400
    todo = {
        'id': todo_id_counter,
        'title': data['title'],
        'completed': False
    }
    todos.append(todo)
    todo_id_counter += 1
    return jsonify(todo), 201

@app.route('/todos/<int:todo_id>', methods=['PUT'])
def update_todo(todo_id):
    data = request.get_json()
    for todo in todos:
        if todo['id'] == todo_id:
            if 'title' in data:
                todo['title'] = data['title']
            if 'completed' in data:
                todo['completed'] = data['completed']
            return jsonify(todo)
    return jsonify({'error': 'not found'}), 404

@app.route('/todos/<int:todo_id>', methods=['DELETE'])
def delete_todo(todo_id):
    global todos
    todos = [t for t in todos if t['id'] != todo_id]
    return '', 204

if __name__ == '__main__':
    app.run(debug=True, port=5000)

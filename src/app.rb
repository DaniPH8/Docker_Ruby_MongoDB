require 'sinatra'
require 'mongo'
require 'json'

set :bind, '0.0.0.0'
set :port, 3000

# Conexión a MongoDB
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# --- R (READ): Listar cursos y mostrar interfaz ---
get '/' do
  lista_html = cursos_col.find.map do |curso|
    id = curso[:_id].to_s
    "
    <li style='margin-bottom: 10px; padding: 10px; border: 1px solid #ddd; display: flex; justify-content: space-between; align-items: center;'>
      <span><b>#{curso[:titulo]}</b> - #{curso[:duracion]} (#{curso[:precio]})</span>
      <div style='display: flex; gap: 5px;'>
        <a href='/editar/#{id}' style='text-decoration: none; padding: 5px 10px; background: #ffc107; color: black; border-radius: 4px;'>✏️</a>
        <form action='/borrar/#{id}' method='POST' style='margin: 0;' onsubmit=\"return confirm('¿Estás seguro de borrar este curso?');\">
          <button type='submit' style='padding: 5px 10px; background: #dc3545; color: white; border: none; border-radius: 4px; cursor: pointer;'>🗑️</button>
        </form>
      </div>
    </li>
    "
  end.join

  "
  <div style='font-family: sans-serif; max-width: 800px; margin: 20px auto;'>
    
    <div style='display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #eee; padding-bottom: 10px; margin-bottom: 20px;'>
      <h1 style='margin: 0;'>🎓 Gestión de Cursos</h1>
      
      <form action='/subir-git' method='POST' style='margin: 0;'>
        <button type='submit' style='padding: 8px 15px; background: #0d6efd; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; font-weight: bold;'>
          ☁️ Push a Git
        </button>
      </form>
    </div>

    <h3>Listado actual:</h3>
    <ul style='list-style: none; padding: 0;'>#{lista_html.empty? ? '<li><i>No hay cursos todavía</i></li>' : lista_html}</ul>

    <hr style='margin: 30px 0;'>

    <h3>➕ Crear Nuevo Curso:</h3>
    #{form_curso('/nuevo', 'Guardar Curso')}
  </div>
  "
end

# --- LÓGICA DE GIT ---
post '/subir-git' do
  begin
    # 1. Exportar JSON
    datos = cursos_col.find.to_a
    datos.each { |d| d[:_id] = d[:_id].to_s }
    File.write('backup_cursos.json', JSON.pretty_generate(datos))

    # 2. Ejecutar Git
    cmd = "git add . && git commit -m 'Backup desde web' && git push origin main"
    
    if system(cmd)
      "<h1>✅ Guardado</h1><p>Backup creado y subido a GitHub.</p><a href='/'>Volver</a>"
    else
      "<h1>❌ Error</h1><p>Revisa la terminal de Docker.</p><a href='/'>Volver</a>"
    end
  rescue StandardError => e
    "Error: #{e.message}"
  end
end

# --- RESTO DEL CRUD ---
post '/nuevo' do
  cursos_col.insert_one({ titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio] })
  redirect '/'
end

get '/editar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  curso = cursos_col.find(_id: id).first
  "<div style='font-family: sans-serif; max-width: 600px; margin: 20px auto;'><h1>✏️ Editar</h1>#{form_curso("/actualizar/#{params[:id]}", 'Actualizar', curso[:titulo], curso[:duracion], curso[:precio])}<br><a href='/'>Cancelar</a></div>"
end

post '/actualizar/:id' do
  cursos_col.update_one({ _id: BSON::ObjectId.from_string(params[:id]) }, { '$set' => { titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio] }})
  redirect '/'
end

post '/borrar/:id' do
  cursos_col.delete_one(_id: BSON::ObjectId.from_string(params[:id]))
  redirect '/'
end

def form_curso(accion, btn_txt, tit='', dur='', pre='')
  "<form action='#{accion}' method='POST' style='display: flex; flex-direction: column; gap: 10px; background: #f9f9f9; padding: 15px; border-radius: 5px;'>
    <input type='text' name='titulo' value='#{tit}' placeholder='Nombre del curso' required style='padding: 8px;'>
    <input type='text' name='duracion' value='#{dur}' placeholder='Duración (ej: 10h)' required style='padding: 8px;'>
    <input type='text' name='precio' value='#{pre}' placeholder='Precio (ej: 15€)' required style='padding: 8px;'>
    <button type='submit' style='padding: 10px; background: #28a745; color: white; border: none; cursor: pointer; font-weight: bold;'>#{btn_txt}</button>
  </form>"
end
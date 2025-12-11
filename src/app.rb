require 'sinatra'
require 'mongo'
require 'json'
require 'fileutils'

set :bind, '0.0.0.0'
set :port, 3000

# Configuración de carpeta pública para imágenes
set :public_folder, File.join(File.dirname(__FILE__), '../public')

# Conexión MongoDB
client = Mongo::Client.new('mongodb://mongodb:27017/plataforma_cursos')
cursos_col = client[:cursos]

# --- VISTA PRINCIPAL ---
get '/' do
  cards_html = cursos_col.find.map do |curso|
    id = curso[:_id].to_s
    # Usamos una imagen de placeholder gris si no hay imagen subida
    img_path = curso[:imagen] ? "/uploads/#{curso[:imagen]}" : "https://via.placeholder.com/400x250/e9ecef/adb5bd?text=Curso+Sin+Imagen"
    
    "
    <div class='col-md-4 mb-4'>
      <div class='card h-100 shadow-sm border-0'>
        <img src='#{img_path}' class='card-img-top rounded-top' alt='Curso' 
             style='height: 220px; object-fit: cover; object-position: center; background-color: #f0f0f0;'>
        
        <div class='card-body'>
          <h5 class='card-title fw-bold text-dark'>#{curso[:titulo]}</h5>
          <div class='mb-2'>
            <span class='badge bg-light text-dark border'>⏱️ #{curso[:duracion]}</span>
            <span class='badge bg-success bg-opacity-75'>🏷️ #{curso[:precio]}</span>
          </div>
        </div>
        <div class='card-footer bg-white border-top-0 d-flex justify-content-between py-3'>
          <a href='/editar/#{id}' class='btn btn-outline-primary btn-sm fw-bold px-3'>✏️ Editar</a>
          <form action='/borrar/#{id}' method='POST' style='margin:0;' onsubmit=\"return confirm('¿Borrar curso?');\">
            <button type='submit' class='btn btn-outline-danger btn-sm px-3'>🗑️ Borrar</button>
          </form>
        </div>
      </div>
    </div>
    "
  end.join

  layout(
    "
    <div class='p-5 mb-5 bg-dark text-white rounded-3 shadow-sm' style='background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);'>
      <div class='container-fluid py-2 text-center text-md-start'>
        <h1 class='display-4 fw-bold'>Mis Cursos Online</h1>
        <p class='fs-5 col-md-8'>Catálogo profesional gestionado con Ruby, Mongo y Git.</p>
        <a href='#form-crear' class='btn btn-light text-primary fw-bold btn-lg mt-3 shadow-sm'>+ Subir Nuevo Curso</a>
      </div>
    </div>

    <div class='container'>
      <div class='d-flex justify-content-between align-items-center mb-4 border-bottom pb-2'>
        <h3 class='m-0 fw-bold text-secondary'>📚 Catálogo Disponible</h3>
      </div>
      
      <div class='row'>
        #{cards_html.empty? ? '<div class="col-12"><div class="alert alert-info text-center shadow-sm p-5"><h4>📭 Catálogo vacío</h4><p>Usa el formulario de abajo para añadir tu primer curso con imagen.</p></div></div>' : cards_html}
      </div>
    </div>

    <div class='container mt-5 mb-5' id='form-crear' style='max-width: 700px;'>
      <div class='card shadow-lg border-0'>
        <div class='card-header bg-primary text-white py-3 fw-bold'>
          ➕ Añadir Nuevo Curso al Catálogo
        </div>
        <div class='card-body p-4'>
          #{form_curso('/nuevo', 'Guardar Curso')}
        </div>
      </div>
    </div>
    "
  )
end

# --- GIT PUSH ---
post '/subir-git' do
  begin
    datos = cursos_col.find.to_a
    datos.each { |d| d[:_id] = d[:_id].to_s }
    File.write('backup_cursos.json', JSON.pretty_generate(datos))

    cmd = "git add . && git commit -m 'Backup cursos e imagenes' && git push origin main 2>&1"
    output = `#{cmd}`
    
    if $?.success?
      layout("<div class='text-center mt-5 pt-5'><div style='font-size: 80px;'>✅</div><h1 class='text-success fw-bold'>Sincronización Completa</h1><p class='lead'>Código, base de datos e imágenes subidas a GitHub.</p><a href='/' class='btn btn-primary mt-3'>Volver al Catálogo</a></div>")
    else
      layout("<div class='container mt-5 alert alert-danger shadow-sm'><h4 class='alert-heading'>❌ Error en el Push</h4><pre>#{output}</pre><a href='/' class='btn btn-outline-danger mt-2'>Volver</a></div>")
    end
  rescue => e
    "Error: #{e.message}"
  end
end

# --- LOGICA IMAGEN ---
def guardar_imagen(params_imagen)
  return nil unless params_imagen
  filename = "#{Time.now.to_i}_#{params_imagen[:filename]}" # Añadimos timestamp para evitar nombres duplicados
  path = File.join(File.dirname(__FILE__), '../public/uploads', filename)
  File.open(path, 'wb') { |f| f.write(params_imagen[:tempfile].read) }
  filename
end

# --- CRUD ---
post '/nuevo' do
  nombre_imagen = guardar_imagen(params[:imagen])
  cursos_col.insert_one({ titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio], imagen: nombre_imagen })
  redirect '/'
end

post '/actualizar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  update_data = { titulo: params[:titulo], duracion: params[:duracion], precio: params[:precio] }
  if params[:imagen]
    nombre_imagen = guardar_imagen(params[:imagen])
    update_data[:imagen] = nombre_imagen
  end
  cursos_col.update_one({ _id: id }, { '$set' => update_data })
  redirect '/'
end

post '/borrar/:id' do
  # Opcional: Podrías borrar el archivo físico de la imagen aquí también si quisieras limpiar
  cursos_col.delete_one(_id: BSON::ObjectId.from_string(params[:id]))
  redirect '/'
end

get '/editar/:id' do
  id = BSON::ObjectId.from_string(params[:id])
  curso = cursos_col.find(_id: id).first
  layout("
    <div class='container mt-5 mb-5' style='max-width: 600px;'>
      <div class='card shadow'>
        <div class='card-header bg-warning fw-bold'>✏️ Editar: #{curso[:titulo]}</div>
        <div class='card-body p-4'>
          #{form_curso("/actualizar/#{params[:id]}", 'Actualizar Cambios', curso[:titulo], curso[:duracion], curso[:precio], true)}
          <a href='/' class='btn btn-link text-secondary w-100 mt-3'>Cancelar</a>
        </div>
      </div>
    </div>
  ")
end

# --- LAYOUT GLOBAL ---
def layout(contenido)
  "<!DOCTYPE html>
  <html lang='es'>
  <head>
    <meta charset='UTF-8'><meta name='viewport' content='width=device-width, initial-scale=1'>
    <title>Cursos Online</title>
    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
    <style>@import url('https://fonts.googleapis.com/css2?family=Poppins:wght@300;400;600;700&display=swap'); body { font-family: 'Poppins', sans-serif; }</style>
  </head>
  <body class='bg-light'>
    <nav class='navbar navbar-expand-lg navbar-dark bg-dark py-3 shadow-sm'>
      <div class='container'>
        <a class='navbar-brand fw-bold fs-4' href='/'>📷 Cursos online</a>
        <form action='/subir-git' method='POST' class='d-flex m-0'>
          <button type='submit' class='btn btn-outline-light btn-sm fw-bold px-3'>☁️ Push Git</button>
        </form>
      </div>
    </nav>
    #{contenido}
  </body></html>"
end

# --- HELPER FORMULARIO ---
def form_curso(accion, btn_txt, tit='', dur='', pre='', es_edicion=false)
  nota_imagen = es_edicion ? "<small class='text-muted d-block mt-1'>💡 Deja vacío para mantener la imagen actual.</small>" : ""
  req_img = es_edicion ? "" : "" # Puedes poner 'required' si quieres obligar a subir imagen al crear
  
  "<form action='#{accion}' method='POST' enctype='multipart/form-data'>
    <div class='mb-4'>
      <label class='form-label fw-bold'>Título del Curso</label>
      <input type='text' name='titulo' value='#{tit}' class='form-control form-control-lg' placeholder='Ej: Introducción a Docker' required>
    </div>
    <div class='row'>
      <div class='col-md-6 mb-4'>
        <label class='form-label fw-bold'>Duración</label>
        <div class='input-group'>
          <span class='input-group-text'>⏱️</span>
          <input type='text' name='duracion' value='#{dur}' class='form-control' placeholder='Ej: 10h' required>
        </div>
      </div>
      <div class='col-md-6 mb-4'>
        <label class='form-label fw-bold'>Precio</label>
        <div class='input-group'>
          <span class='input-group-text'>€</span>
          <input type='text' name='precio' value='#{pre}' class='form-control' placeholder='Ej: 19.99' required>
        </div>
      </div>
    </div>
    <div class='mb-4 p-3 bg-light rounded border'>
      <label class='form-label fw-bold'>Imagen de Portada</label>
      <input type='file' name='imagen' class='form-control' accept='image/png, image/jpeg' #{req_img}>
      #{nota_imagen}
    </div>
    <div class='d-grid'>
      <button type='submit' class='btn btn-primary btn-lg fw-bold'>#{btn_txt}</button>
    </div>
  </form>"
end
<?php

namespace App\Http\Controllers;

use App\Models\Includes;
use App\Models\Models;
use App\Models\Project;
use App\Models\Snapshot;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Response;
use Illuminate\Support\Facades\Storage;
use League\Flysystem\Filesystem;
use League\Flysystem\ZipArchive\ZipArchiveAdapter;

class ModelController extends Controller
{
    //
    public function simulate(Request $request)
    {
        $user_id = $request->user_id;
        $simulation_id = $request->simulation_id;
        $model = Models::where('id', $simulation_id)->first();
        $project = Project::where("id", $model->project_id)->first();
        $xmlfile = file_get_contents($request->xmlfile);
        $data = [];
        $my_file = '../GAMA/headless/' . $user_id . '_template_run.xml';
        $handle = fopen($my_file, 'w');
        fwrite($handle, $xmlfile);
        fclose($handle);
        $resultDir = $simulation_id . '_outputHeadLess';
        exec('cd ../GAMA/headless; bash gama-headless.sh ' . $user_id . '_template_run.xml ' . $resultDir, $output, $retval);

        $dir = '/var/www/GAMA/headless/' . $simulation_id . '_outputHeadLess/snapshot/*';
        if (glob($dir)) {
            Snapshot::where("simulation_id", $simulation_id)->delete();
            Storage::disk('s3')->delete('snapshots/' . $simulation_id);
            $list = glob($dir);
            natsort($list);
            foreach ($list as $file) {
                $file_name = str_replace('/var/www/GAMA/headless/' . $simulation_id . '_outputHeadLess/snapshot/', '', $file);
                $url = Storage::disk('s3')->putFileAs('snapshots/' . $simulation_id, $file, $file_name);
                $url = Storage::disk('s3')->url($url);
                $file_name = substr($file_name, 0, strpos($file_name, $simulation_id));
                Snapshot::create([
                    'simulation_id' => $simulation_id,
                    'url' => $url,
                    'name' => $file_name,
                ]);
            }
            $output_names = Snapshot::where('simulation_id', $simulation_id)->distinct()->pluck('name');
            foreach ($output_names as $output_name) {
                $urls = Snapshot::where('simulation_id', $simulation_id)->where('name', $output_name)->pluck('url');;
                array_push($data, (object)[
                    'name' => $output_name,
                    'urls' => $urls
                ]);
            }
            $outputdir = "../GAMA/headless/" . $simulation_id . '_outputHeadLess/simulation-outputs' . $simulation_id . '.xml';
            try {
                $file = File::get($outputdir);
                $outputxml = Response::make($file, 200);
            } catch (\Exception $e) {
                $outputxml = null;
            }
            $response = [
                'success' => true,
                'data' => $data,
                'ouputxml' => $outputxml
            ];
        } else {
            $response = [
                'success' => false,
                'message' => "Something went wrong! Please contact admin!"
            ];
            return response($response, 400);
        }
        $dir = "../GAMA/headless/userProjects/" . $request->user_id;
        $modelsDir = $dir . '/' . $project->name . '/models/';
        $includesDir = $dir . '/' . $project->name . '/includes/';
        $scanned_models = S3Controller::getDirContents($modelsDir);
        $scanned_includes = S3Controller::getDirContents($includesDir);
        foreach ($scanned_models as $model) {
            $isExist = Models::where('filename', $model)->first();
            if (!$isExist) {
                Models::create([
                    "id" => uniqid(),
                    "project_id" => $project->id,
                    "filename" => $model
                ]);
            }
        }
        
        foreach ($scanned_includes as $include) {
            $isExist = Includes::where('filename', $include)->first();
            if (!$isExist) {
                Includes::create([
                    "id" => uniqid(),
                    "project_id" => $project->id,
                    "filename" => $include
                ]);
            }
        }


        exec('cd ../GAMA/headless; rm -rf .work*', $output, $retval);
        exec('cd ../GAMA/headless; rm -rf ' . $simulation_id . '_outputHeadLess/snapshot', $output, $retval);
        return response($response, 200)->header('Access-Control-Allow-Origin', '*');

    }

    public function simulateLatest($id)
    {

        $output_names = Snapshot::where('simulation_id', $id)->distinct()->pluck('name');
        $data = [];
        foreach ($output_names as $output_name) {
            $urls = Snapshot::where('simulation_id', $id)->where('name', $output_name)->pluck('url');;
            array_push($data, (object)[
                'name' => $output_name,
                'urls' => $urls
            ]);
        }
        $outputdir = "../GAMA/headless/" . $id . '_outputHeadLess/simulation-outputs' . $id . '.xml';
        try {
            $file = File::get($outputdir);
            $outputxml = Response::make($file, 200);
        } catch (\Exception $e) {
            $outputxml = null;
        }
        $response = [
            'success' => true,
            'data' => $data,
            'ouputxml' => $outputxml
        ];
        return response($response, 200);
    }

    public function buildContentFile($urls, $fps)
    {
        $content = '';
        foreach ($urls as $url) {
            $row1 = "file '" . $url . "'\n";
            $row2 = "duration " . $fps . "\n";
            $content = $content . $row1 . $row2;
        }
        return $content;
    }

    public function simulateDownload($id, Request $request)
    {
        $fps = $request->fps;
        File::delete(File::glob(public_path('*.zip')));
        $output_names = Snapshot::where('simulation_id', $id)->distinct()->pluck('name');
        $resultDir = "../GAMA/headless/" . $id . '_outputHeadLess/';
        $source_disk = 's3';
        $source_path = '/download/' . $id;
        $zip_file_name = $id . '.zip';
        Storage::disk('s3')->delete($source_path);

        foreach ($output_names as $output_name) {
            $urls = Snapshot::where('simulation_id', $id)->where('name', $output_name)->pluck('url');
            $resultTextFile = $resultDir . $output_name . "_output.txt";
            $resultMp4File = $resultDir . $output_name . ".mp4";
            $fileContent = $this->buildContentFile($urls, $fps);
            file_put_contents($resultTextFile, $fileContent);
            exec('ffmpeg -y -protocol_whitelist file,http,https,tcp,tls,crypto -safe 0 -f concat -i ' . $resultTextFile . ' -c:v libx264 -r 30 -pix_fmt yuv420p ' . $resultMp4File, $output, $retval);
            $url = Storage::disk('s3')->putFileAs('download/' . $id, $resultMp4File, $output_name . '.mp4');
            $url = Storage::disk('s3')->url($url);
        }
        exec('cd ' . $resultDir . '; rm -rf *.mp4', $output, $retval);

        $file_names = Storage::disk($source_disk)->files($source_path);
        $zip = new Filesystem(new ZipArchiveAdapter(public_path($zip_file_name)));
        foreach ($file_names as $file_name) {
            $file_content = Storage::disk($source_disk)->get($file_name);
            $zip->put($file_name, $file_content);
        }

        $zip->getAdapter()->getArchive()->close();
        return response()->download(public_path($zip_file_name));
    }
}
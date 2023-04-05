/**
* Name: Verify2020
* Based on the internal empty template. 
* Author: HuyNQ52
* Tags: Add simulation step and verify
*/


model Verify2020

/* Insert your model definition here */

global {
	/* Map files */
	file vMapFile <- file("../includes/QuanHuyen.shp");
	file vMapFileCenter <- file("../includes/TTQuanHuyen.shp");
	geometry shape <- envelope(vMapFile);
	bool vEnable <- true;

	/* Data files */
	file vSFile <- csv_file("../includes/Tmp10TrongDan.csv");
	file vLFile <- csv_file("../includes/CongTy.csv");
	map<string, int> vSNbFarms;
	map<string, int> vSNbTotalPigs;
	map<string, float> vSAvgPigs;
	map<string, int> vLNbFarms;
	map<string, int> vLNbTotalPigs;
	map<string, float> vLAvgPigs;

	int vNbPigsTotal <- 0;
	int cRange <- 20000; 

	// list<int> vNbFarms <- [5499, 1989, 394];		// 5499 Small farms; 1989 Medium farms; 394 Large farms
	// list<int> vNbFarms <- [700, 250, 50];
	list<int> vNbFarms <- [0, 1, 2];
	float cTPDirect <- 0.6; 						// Transmission probability of direct contact
	list<float> vTPIndirect <- [0.6, 0.6, 0.006];	// TP of indirect contact: Small/Medium farms - 0.6; Large farms - 0.006	
	list<int> cDuration <- [52, 52, 4];				// Infectious duration for: Small farm - 52 weeks; Medium farm - 10-12 weeks; Large farm - 4 weeks
	
	
	matrix vCRDirect 	<- matrix([[0.072, 0, 0], [0.072, 0.073, 0], [0, 0.073, 0]]); // Mean direct contact rate/week. vCRDirect[2,1] - Mean direct contact rate of Large farm to Medium farm = 0.073
	matrix vCRIndirect 	<- matrix([[0.282, 0.282, 0], [0.282, 0.271, 3.5], [0, 0.271, 3.5]]); // Mean indirect contact rate/week. vCRIndirect[2,1] - Mean indirect contact rate of Large farm to Medium farm = 0.271
	
	// matrix vCRDirect 	<- matrix([[0.072, 0, 0], [0.072, 0.073, 0], [0, 0.073, 0]]);
	// matrix vCRIndirect 	<- matrix([[0.141, 0.282, 0], [0.282, 0.271, 3.5], [0, 0.271, 3.5]]);

	bool pEnDist <- true;
	bool pEnDirect <- true;
	bool pEnLarge <- true;
	float pKTPIndirect <- 1.0; 	// Indirect TP change - New indirect TP = vKIndirect * old indirect TP
	float pKMove <- 1.0;		// Movement control rate - 1: No movement restriction; 0: Movement restriction 100%	
	int pMoveRTime <- 4;		// Movement restriction within 4 weeks of detection of outbreaks 
	// int vCullTime <- 53;		// Culling within 53 weeks of detection of outbreaks. It mean no culling in the simulation time
	int pDays <- 7; 		// Number of days per 1 simulation step

	int vNbContacts <- 0;
	map vNbInfectedFarms <- [0::0, 1::1, 2::0];

	matrix verifyCRDirect 	<- matrix([[0.0, 0, 0], [0.0, 0.0, 0], [0, 0.0, 0]]);
	matrix verifyCRIndirect <- matrix([[0.0, 0.0, 0], [0.0, 0.0, 0.0], [0, 0.0, 0.0]]);
	int verifyDirectContacts <- 0;
	int verifyIndirectContacts <- 0;
	int verifyNbContacts <- 0;

	init {
		/* Initialize maps */
		create sDistrict from: vMapFile with: [aNameEN::string(read("ADM2_EN"))];
		create sDistrictCenter from: vMapFileCenter with: [aNameVN::string(read("ADM2_VI"))];
		
		/* Parse data */
		int i <- 0;
		string vKey;

		loop it over: vSFile {	// Note: Auto ignore first line
			if (mod(i, 4) = 0) {
				vKey <- it;	
			} 
			else if (mod(i, 4) = 1) {
				add int(it) at: vKey to: vSNbFarms;
			}
			else if (mod(i, 4) = 2) {
				add int(it) at: vKey to: vSNbTotalPigs;
			}
			else {
				add int(it) at: vKey to: vSAvgPigs;
			}
			write string(i) + ". " + vKey;
			i <- i + 1;
		}
		
		i <- 0;
		loop it over: vLFile { // Note: Auto ignore first line
			if (mod(i, 4) = 0) {
				vKey <- it;	
			} 
			else if (mod(i, 4) = 1) {
				add int(it) at: vKey to: vLNbFarms;
			}
			else if (mod(i, 4) = 2) {
				add int(it) at: vKey to: vLNbTotalPigs;
			}
			else {
				add int(it) at: vKey to: vLAvgPigs;
			}
			i <- i + 1;
		}
	
		/* Initilize farms */
		sDistrict vDistrict;
		i <- 0;
		write "Initialize farms...";
		loop vDistrict over: sDistrict {
			/* Chăn nuôi trong dân */
			i <- i + 1;
			write string(i) + "/30 " + vDistrict.aNameEN;
			vDistrict.aNbFarms <- (vSNbFarms.pairs first_with (each.key = vDistrict.aNameEN)).value;
			loop times: vDistrict.aNbFarms {
				create sFarm number: 1 {
					aType <- 0;
					location <- any_location_in(vDistrict);
					aNbPigs <- poisson((vSAvgPigs.pairs first_with (each.key = vDistrict.aNameEN)).value);
			      	if (aNbPigs < 30) {
						aType <- 0;
					} else if (aNbPigs < 300) {
						aType <- 1;
					} else {
						aType <- 2;
					}
					vNbFarms[aType] <- vNbFarms[aType] + 1;
			      	vNbPigsTotal <- vNbPigsTotal + aNbPigs;
			      	vDistrict.aNbPigs <- vDistrict.aNbPigs + aNbPigs;
				}
			}
			
			/* Chăn nuôi trong cơ sở chăn nuôi */
			int vNbLoop <- (vLNbFarms.pairs first_with (each.key = vDistrict.aNameEN)).value;
			vDistrict.aNbFarms <- vDistrict.aNbFarms + vNbLoop;
			loop times: vNbLoop {
				create sFarm number: 1 {
					location <- any_location_in(vDistrict);
					aNbPigs <- round((vLAvgPigs.pairs first_with (each.key = vDistrict.aNameEN)).value);
					if (aNbPigs < 30) {
						aType <- 0;
					} else if (aNbPigs < 300) {
						aType <- 1;
					} else {
						aType <- 2;
					}
					vNbFarms[aType] <- vNbFarms[aType] + 1;
			      	vNbPigsTotal <- vNbPigsTotal + aNbPigs;
			      	vDistrict.aNbPigs <- vDistrict.aNbPigs + aNbPigs;
				}
			}
		}
		write "Total pigs: " + vNbPigsTotal;
		write "Total Farms: " + (vNbFarms[0] + vNbFarms[1] + vNbFarms[2]) + " - " + vNbFarms;

		/* Initialize infected farms */
		loop while: true {
			sFarm vFarm <- one_of(sFarm);
			if vFarm.aType = 1 {
				vFarm.isInfected <- true;
				break;
			}
		}
	}

	reflex rInfo when: cycle > 0 and mod(cycle,int(cDuration[0] * 7/pDays /2)) = 0 {
		write "Cycle: " + cycle + " - vNbInfectedFarms: " + vNbInfectedFarms;
	}

	reflex rParseParams when: cycle = 0 {
		
		if !pEnDirect {
			write "Disable Direct contacts";
			vCRDirect 	<- matrix([[0.0, 0, 0], [0.0, 0.0, 0], [0, 0.0, 0]]);
		}
		loop i from: 0 to: 2 {
			loop j from: 0 to: 2 {
				if !pEnLarge {
					if i = 2 or j = 2 {
						vCRDirect[i,j] <- 0;
						vCRIndirect[i,j] <- 0;
					}
				}
			}
		}
		vTPIndirect <- [pKTPIndirect * vTPIndirect[0], pKTPIndirect * vTPIndirect[1], vTPIndirect[2]];
		write "New vTPIndirect: " + vTPIndirect;
	}

	reflex rInfo when: cycle > 0 and mod(cycle,int(cDuration[0] * 7/pDays /2)) = 0 {
		write "Cycle: " + cycle + " - vNbInfectedFarms: " + vNbInfectedFarms;
	}

	reflex rPause when: cycle = 52 { 
		write "Pause"; 
		do pause;
	}

	reflex rInitContacts {
		vNbContacts <- 0;
		verifyDirectContacts <- 0;
		verifyIndirectContacts <- 0;
		verifyNbContacts <- 0;
		int vTmp <- 0;
		ask sFarm {
			aDirectNew <- [0::[], 1::[], 2::[]];
			aIndirectNew <- [0::[], 1::[], 2::[]];
			/* Regenerate number of contacts */
			loop i from: 0 to: 2 {
				if aInfectedDays > pMoveRTime {
					// write " Movement restriction: " + name;
					aNbDirect[i] 	<- poisson(pKMove * vCRDirect[aType, i] * pDays/7);
					aNbIndirect[i] 	<- poisson(pKMove * vCRIndirect[i, aType] * pDays/7);
				} else {
					aNbDirect[i] 	<- poisson(vCRDirect[aType, i] * pDays/7);
					aNbIndirect[i] 	<- poisson(vCRIndirect[i, aType] * pDays/7);
				}
				vNbContacts <- vNbContacts + aNbDirect[i];
				vNbContacts <- vNbContacts + aNbIndirect[i];
				verifyDirectContacts <- verifyDirectContacts + aNbDirect[i];
				verifyIndirectContacts <- verifyIndirectContacts + aNbIndirect[i];
				verifyCRDirect[aType, i] <- verifyCRDirect[aType, i] + aNbDirect[i];
				verifyCRIndirect[i, aType] <- verifyCRIndirect[i, aType] + aNbIndirect[i];
			}
		}

		/* Create contacts */
		ask sFarm {

			/* Create direct contacts */
			loop i from: 0 to: 2 {
				vTmp <- vTmp + aNbDirect[i] - length(aDirect[i]);
				loop times: aNbDirect[i] - length(aDirect[i]) {
					ask sFarm at_distance cRange {
						if self != myself and self.aType = i {
							add self to: myself.aDirect[i];
							break;
						}
					}
				}
				verifyNbContacts <- verifyNbContacts + length(aDirect[i]);
			}

			/* Create indirect contacts */
			loop i from: 0 to: 2 {
				vTmp <- vTmp + aNbIndirect[i] - length(aIndirect[i]);
				loop times: aNbIndirect[i] - length(aIndirect[i]) {
					ask sFarm at_distance cRange {
						if self != myself and (self.aType = i) {
							add self to: myself.aIndirect[i];
							break;
						}
					}
				}
				verifyNbContacts <- verifyNbContacts + length(aIndirect[i]);
			}
		}

		ask sFarm {
			loop i from: 0 to: 2 {
				loop vFarm over: (aNbIndirect[i] among aIndirect[i]) {
					add self to: vFarm.aIndirectNew[aType];
				}
			}
		}
	}
}

species sDistrictCenter {
	string aNameVN <- nil;
	aspect default {
		if vEnable {
			draw circle(100) color: #yellow;
			draw aNameVN color: #black font: font('Default', 15, #bold) at: {location.x, location.y};
		}
	}
}

species sFarm schedules: shuffle(sFarm) {
	int aType <- 3; 	// 0 - Small farm; 1 - Medium farm; 2 - Large farm
	bool isInfected <- false;
	int aInfectedDays <- 0;
	map<int,list<sFarm>> aDirect 	<- [0::[], 1::[], 2::[]];
	map<int,list<sFarm>> aIndirect 	<- [0::[], 1::[], 2::[]];
	map<int,list<sFarm>> aDirectNew <- [0::[], 1::[], 2::[]];
	map<int,list<sFarm>> aIndirectNew <- [0::[], 1::[], 2::[]];
	map<int,int> aNbDirect 			<- [0::0, 1::0, 2::0];
	map<int,int> aNbIndirect 		<- [0::0, 1::0, 2::0];
	int aNbPigs <- 0;

	reflex rUpdate when: isInfected {
		aInfectedDays <- aInfectedDays + 1;
	}

	reflex rInfect when: isInfected {
		loop i from: 0 to: 2 {
			loop vFarm over: (aNbDirect[i] among aDirect[i]) {
				if not(vFarm.isInfected) {
					if flip(cTPDirect) {
						vFarm.isInfected <- true;
						vNbInfectedFarms[vFarm.aType] <- vNbInfectedFarms[vFarm.aType] + 1;
					}
				}
			}
			loop vFarm over: (aIndirectNew[i]) {
				if not(vFarm.isInfected) {
					float vTP <- vTPIndirect[vFarm.aType];
					if aInfectedDays > pMoveRTime {
						vTP <- pKMove * vTP;
					}
					if flip(vTP) {
						vFarm.isInfected <- true;
						vNbInfectedFarms[vFarm.aType] <- vNbInfectedFarms[vFarm.aType] + 1;
					}
				}
			}
		}
	}
	aspect default {
		int tmp <-  aType = 0 ? 200 : (aType = 1 ? 300 : 500);
	    draw circle(tmp) color: isInfected ? #red : #green; 
	}	
}

species sDistrict {
	string aNameEN <- nil;
	bool isInfected <- false;
	int aNbFarms <- 0;
	int aNbFarmsInfected <- 0;
	int aNbPigs <- 0;
	aspect default {
		if (aNbFarms = 0) {
			draw shape color: #gray border: #black;
		} else {
			aNbFarmsInfected <- 0;
			ask sFarm at_distance 0 {
				if (isInfected) {
					myself.isInfected <- true;
					myself.aNbFarmsInfected <- myself.aNbFarmsInfected + 1;
				}
			}
			
			draw shape color: isInfected ? hsb(aNbFarmsInfected/aNbFarms*(0.71-0.47)+0.47, 1, 1) : #gray border: #black;
		}	
	}
}

// experiment eExp type: batch repeat: 16 keep_seed: false until: cycle = cDuration[0] * 7/pDays + 1 {
experiment eExp type: gui {
	// reflex rWrite{
	// 	write "End simulation";
	// }
	parameter "Show District Name" category: "Display" var: vEnable <- true; 
	parameter "Enable Direct contacts: " 	category: "Parameters" var: pEnDirect 	<- true;
	parameter "Enable Large farm contacts: " category: "Parameters" var: pEnLarge 	<- true;
	parameter "Days/Simulation step: " category: "Parameters" var: pDays <- 7 among: [1,2,7];
	parameter "Movement restriction: " category: "Parameters" var: pKMove <- 1.0 min: 0.0 max: 1.0 step: 0.25;
	parameter "Movement restriction timing: " category: "Parameters" var: pMoveRTime <- 4 min: 2 max: 8 step: 2;
	parameter "Indirect contact factor: " category: "Parameters" var: pKTPIndirect <- 1.0 min: 0.0 max: 1.0 step: 0.25;
	output {
		display myDisplay {
			species sDistrict aspect: default;
			species sFarm aspect: default;
			species sDistrictCenter aspect: default;
		}
	 	display myChart refresh: every(1 #cycles) {
	 		chart "Số trang trại bị nhiễm bệnh" {
	 			data "Small" value: vNbInfectedFarms[0] color: #red;
	 			data "Medium" value: vNbInfectedFarms[1] color: #orange;
	 			data "Large" value: vNbInfectedFarms[2] color: #green;
	 			data "Total" value: vNbInfectedFarms[0] + vNbInfectedFarms[1] + vNbInfectedFarms[2] color: #black;
	 		}
	 	}
	 	display myChart1 refresh: every(1 #cycles) {
	 		chart "Phần trăm trại bị nhiễm bệnh" {
	 			data "Small" value: vNbInfectedFarms[0]/vNbFarms[0] color: #red;
	 			data "Medium" value: vNbInfectedFarms[1]/vNbFarms[1] color: #orange;
	 			data "Large" value: vNbInfectedFarms[2]/vNbFarms[2] color: #green;
	 		}
	 	}
	 }
}